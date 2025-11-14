// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol"; //椭圆曲线加密
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

interface IHasTrustedForwarder {
    function trustedForwarder() external view returns (address);
}

//无权限元交易转发器，支持 “代付 Gas 费” 的交易模式。
contract BasicForwarder is EIP712 {
    struct Request {
        address from; //发送消息的地址
        address target; //最终被调用的合约
        uint256 value;
        uint256 gas;
        uint256 nonce; //随机数 / 计数器（防止请求重放攻击）
        bytes data; //编码后的函数调用数据
        uint256 deadline; //请求有效期
    }

    error InvalidSigner();
    error InvalidNonce();
    error OldRequest();
    error InvalidTarget();
    error InvalidValue();

    bytes32 private constant _REQUEST_TYPEHASH = keccak256(
        "Request(address from,address target,uint256 value,uint256 gas,uint256 nonce,bytes data,uint256 deadline)"
    );

    mapping(address => uint256) public nonces;

    /**
     * @notice Check request and revert when not valid. A valid request must:
     * - Include the expected value
     * - Not be expired
     * - Include the expected nonce
     * - Target a contract that accepts this forwarder
     * - Be signed by the original sender (`from` field)
     */
    //判断该交易请求是否是合法有效的（必须是用户自己发起的请求或者用户让信任的人得到他的singnature然后代为发送）
    function _checkRequest(Request calldata request, bytes calldata signature) private view {
        //确保发送的 ETH 数量和请求中的 value 字段一致
        if (request.value != msg.value) revert InvalidValue();
        //确保请求未过期
        if (block.timestamp > request.deadline) revert OldRequest();
        //确保请求的随机数/计数器正确，防止重放攻击
        if (nonces[request.from] != request.nonce) revert InvalidNonce();
        //pool中以变量的形式实现了接口中的函数名，solidity会自动生成getter函数。
        //判断合约目标是否接受该转发器
        if (IHasTrustedForwarder(request.target).trustedForwarder() != address(this)) revert InvalidTarget();

        //通过交易签名反推出真实的签名者地址
        address signer = ECDSA.recover(_hashTypedData(getDataHash(request)), signature);
        if (signer != request.from) revert InvalidSigner();
    }

    //signature是用户对请求的签名（签名是同构消息哈希和私钥生成的）
    //execute函数执行转发请求
    function execute(Request calldata request, bytes calldata signature) public payable returns (bool success) {
        _checkRequest(request, signature);

        nonces[request.from]++;

        uint256 gasLeft;
        uint256 value = request.value; // in wei
        address target = request.target;
        //payload: [multicallData] + [player地址],而multicallData = [multicall选择器] + [11个调用数据的数组编码]
        // payload 让 Pool 知道：
        //"请执行 multicall 函数，参数是这个包含11个调用的数组"
        //payload 末尾的 player地址 让 Pool 知道：
        //"这个请求的原始发送者是 player"
        bytes memory payload = abi.encodePacked(request.data, request.from); //将from地址附加在data末尾到payload
        uint256 forwardGas = request.gas;
        assembly {
            success := call(forwardGas, target, value, add(payload, 0x20), mload(payload), 0, 0) // don't copy returndata
            gasLeft := gas()
        }

        if (gasLeft < request.gas / 63) {
            assembly {
                invalid()
            }
        }
    }

    // 重写 EIP712 的域名和版本方法
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "BasicForwarder";
        version = "1";
    }

    function getDataHash(Request memory request) public pure returns (bytes32) {
        return keccak256(
            abi.encode(
                _REQUEST_TYPEHASH,
                request.from,
                request.target,
                request.value,
                request.gas,
                request.nonce,
                keccak256(request.data),
                request.deadline
            )
        );
    }

    //外部接口，获取域分隔符
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparator();
    }

    //外部接口，获取请求类型哈希
    function getRequestTypehash() external pure returns (bytes32) {
        return _REQUEST_TYPEHASH;
    }
}
