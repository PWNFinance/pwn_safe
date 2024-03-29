// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import "@safe/proxies/GnosisSafeProxy.sol";
import "@safe/common/Enum.sol";
import "@safe/GnosisSafe.sol";

import "@pwn-safe/factory/PWNSafeFactory.sol";


abstract contract PWNSafeFactoryTest is Test {

    PWNSafeFactory factory;
    address singleton = makeAddr("singleton");
    address gsProxyFactory = makeAddr("gsProxyFactory");
    address fallbackHandler = makeAddr("fallbackHandler");
    address module = makeAddr("module");
    address guard = makeAddr("guard");
    address safe = makeAddr("safe");

    event PWNSafeDeployed(address indexed safe);

    function setUp() public virtual {
        factory = new PWNSafeFactory(
            singleton,
            gsProxyFactory,
            fallbackHandler,
            module,
            guard
        );

        vm.etch(gsProxyFactory, bytes("data"));
        vm.etch(safe, bytes("data"));

        vm.mockCall(
            gsProxyFactory,
            abi.encodeWithSignature("createProxy(address,bytes)", singleton, ""),
            abi.encode(safe)
        );
        vm.mockCall(
            gsProxyFactory,
            abi.encodeWithSignature("proxyRuntimeCode()"),
            abi.encode(type(GnosisSafeProxy).runtimeCode)
        );
    }

}


/*----------------------------------------------------------*|
|*  # CONSTRUCTOR                                           *|
|*----------------------------------------------------------*/

contract PWNSafeFactory_Constructor_Test is PWNSafeFactoryTest {

    function test_shouldFail_whenSafeSingletonIsZeroAddress() external {
        vm.expectRevert("Safe signleton is zero address");
        factory = new PWNSafeFactory(
            address(0),
            gsProxyFactory,
            fallbackHandler,
            module,
            guard
        );
    }

    function test_shouldFail_whenSafeProxyFactoryIsZeroAddress() external {
        vm.expectRevert("Safe proxy factory is zero address");
        factory = new PWNSafeFactory(
            singleton,
            address(0),
            fallbackHandler,
            module,
            guard
        );
    }

    function test_shouldFail_whenFallbackHandlerIsZeroAddress() external {
        vm.expectRevert("Fallback handler is zero address");
        factory = new PWNSafeFactory(
            singleton,
            gsProxyFactory,
            address(0),
            module,
            guard
        );
    }

    function test_shouldFail_whenATRModuleIsZeroAddress() external {
        vm.expectRevert("ATR module is zero address");
        factory = new PWNSafeFactory(
            singleton,
            gsProxyFactory,
            fallbackHandler,
            address(0),
            guard
        );
    }

    function test_shouldFail_whenATRGuardIsZeroAddress() external {
        vm.expectRevert("ATR guard is zero address");
        factory = new PWNSafeFactory(
            singleton,
            gsProxyFactory,
            fallbackHandler,
            module,
            address(0)
        );
    }

}


/*----------------------------------------------------------*|
|*  # DEPLOY PROXY                                          *|
|*----------------------------------------------------------*/

contract PWNSafeFactory_DeployProxy_Test is PWNSafeFactoryTest {

    uint256 threshold = 2;

    function _owners() internal pure returns (address[] memory owners) {
        owners = new address[](3);
        owners[0] = address(0x1000);
        owners[1] = address(0x1001);
        owners[2] = address(0x1002);
    }


    function test_shouldCreateNewGnosisSafeProxy() external {
        vm.expectCall(
            gsProxyFactory,
            abi.encodeWithSignature("createProxy(address,bytes)", singleton, "")
        );
        factory.deployProxy(_owners(), threshold);
    }

    function test_shouldCallSetupOnSafe() external {
        vm.expectCall(
            safe,
            abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                _owners(),
                threshold,
                address(factory),
                abi.encodeWithSelector(PWNSafeFactory.setupNewSafe.selector),
                fallbackHandler,
                address(0),
                0,
                payable(address(0))
            )
        );
        factory.deployProxy(_owners(), threshold);
    }

    function test_shouldMarkSafeAsValid() external {
        factory.deployProxy(_owners(), threshold);

        bytes32 isValid = vm.load(address(factory), keccak256(abi.encode(safe, uint256(0))));
        assertEq(uint256(isValid), 1);
    }

    function test_shouldEmit_PWNSafeDeployed() external {
        vm.expectEmit(true, false, false, false);
        emit PWNSafeDeployed(safe);

        factory.deployProxy(_owners(), threshold);
    }

    function test_shouldReturnNewGnosisSafeProxy() external {
        GnosisSafe newSafe = factory.deployProxy(_owners(), threshold);

        assertEq(address(newSafe), safe);
    }

}


/*----------------------------------------------------------*|
|*  # SETUP NEW SAFE                                        *|
|*----------------------------------------------------------*/

contract PWNSafeFactory_SetupNewSafe_Test is PWNSafeFactoryTest {

    bytes32 internal constant GUARD_STORAGE_SLOT = 0x4a204f620c8c5ccdca3fd54d003badd85ba500436a431f0cbda4f558c93c34c8;
    address internal constant SENTINEL_MODULES = address(0x1);
    address internal constant SENTINEL_OWNERS = address(0x1);

    address alice = address(0xa11ce);
    bytes signature = abi.encodePacked(bytes32(uint256(uint160(alice))), bytes32(0), uint8(1));

    function setUp() public override {
        singleton = address(new GnosisSafe());
        super.setUp();
    }

    function _mockSafe(bytes memory runtimeCode, address _singleton) private {
        vm.etch(safe, runtimeCode);
        // Store singleton
        vm.store(safe, bytes32(uint256(0)), bytes32(uint256(uint160(_singleton))));
        // Store alice as owner
        vm.store(safe, keccak256(abi.encode(alice, bytes32(uint256(2)))), bytes32(uint256(uint160(SENTINEL_OWNERS))));
        // Store number of owners
        vm.store(safe, bytes32(uint256(3)), bytes32(uint256(1)));
        // Store threshold
        vm.store(safe, bytes32(uint256(4)), bytes32(uint256(1)));
    }

    function _callFactory() private {
        GnosisSafe(payable(safe)).execTransaction(
            address(factory),
            0,
            abi.encodeWithSignature("setupNewSafe()"),
            Enum.Operation.DelegateCall,
            0,
            100000,
            0,
            address(0),
            payable(address(0)),
            signature
        );
    }


    function test_shouldFail_whenCalledDirectly() external {
        vm.expectRevert("Should only be called via delegatecall");
        factory.setupNewSafe();
    }

    function test_shouldFail_whenCallerIsNotGnosisSafeProxy() external {
        _mockSafe(type(GnosisSafe).runtimeCode, singleton);

        // Caller is not gnosis safe proxy
        vm.expectRevert("GS013");
        vm.prank(alice);
        _callFactory();
    }

    function test_shouldFail_whenProxyHasWrongSigleton() external {
        GnosisSafe wrongSingleton = new GnosisSafe();
        _mockSafe(type(GnosisSafeProxy).runtimeCode, address(wrongSingleton));

        // Proxy has unsupported singleton
        vm.expectRevert("GS013");
        vm.prank(alice);
        _callFactory();
    }

    function test_shouldStoreATRModuleAndGuard() external {
        _mockSafe(type(GnosisSafeProxy).runtimeCode, singleton);

        vm.prank(alice);
        _callFactory();

        // Check that sentinel key stores module address
        bytes32 sentinelValue = vm.load(safe, keccak256(abi.encode(SENTINEL_MODULES, uint256(1))));
        assertEq(sentinelValue, bytes32(uint256(uint160(module))));
        // Check that modules address key stores sentinel value
        bytes32 moduleValue = vm.load(safe, keccak256(abi.encode(module, uint256(1))));
        assertEq(moduleValue, bytes32(uint256(uint160(SENTINEL_MODULES))));
        // Check stored guard address
        bytes32 guardValue = vm.load(safe, GUARD_STORAGE_SLOT);
        assertEq(guardValue, bytes32(uint256(uint160(guard))));
    }

}
