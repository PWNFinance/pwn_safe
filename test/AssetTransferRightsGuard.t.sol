// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import "../src/guard/AssetTransferRightsGuard.sol";


abstract contract AssetTransferRightsGuardTest is Test {

	bytes32 internal constant ATR_SLOT = bytes32(uint256(0));
	bytes32 internal constant OPERATORS_CONTEXT_SLOT = bytes32(uint256(1));
	address internal constant erc1820Registry = address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

	AssetTransferRightsGuard guard;
	address module = address(0x7701);
	address operators = address(0x7702);
	address safe = address(0x2afe);
	address token = address(0x070ce2);
	address alice = address(0xa11ce);

	constructor() {
		// ERC1820 Registry
		vm.etch(erc1820Registry, bytes("data"));
		vm.mockCall(
			erc1820Registry,
			abi.encodeWithSignature("getInterfaceImplementer(address,bytes32)"),
			abi.encode(address(0))
		);
		vm.etch(module, bytes("data"));
		vm.etch(operators, bytes("data"));
	}

	function setUp() external {
		guard = new AssetTransferRightsGuard();
		guard.initialize(module, operators);
	}

}


/*----------------------------------------------------------*|
|*  # INITIALIZE                                            *|
|*----------------------------------------------------------*/

contract AssetTransferRightsGuard_Initialize_Test is AssetTransferRightsGuardTest {

	function test_shouldSetParams() external {
		guard = new AssetTransferRightsGuard();
		guard.initialize(module, operators);

		// Check atr module value (need to shift by 2 bytes to clear Initializable properties)
		bytes32 atrValue = vm.load(address(guard), ATR_SLOT) >> 16;
		assertEq(atrValue, bytes32(uint256(uint160(module))));
		// Check operators context value
		bytes32 operatorsValue = vm.load(address(guard), OPERATORS_CONTEXT_SLOT);
		assertEq(operatorsValue, bytes32(uint256(uint160(operators))));
	}

	function test_shouldFail_whenCalledSecondTime() external {
		guard = new AssetTransferRightsGuard();
		guard.initialize(module, operators);

		vm.expectRevert("Initializable: contract is already initialized");
		guard.initialize(module, operators);
	}

}


/*----------------------------------------------------------*|
|*  # CHECK TRANSACTION                                     *|
|*----------------------------------------------------------*/

contract AssetTransferRightsGuard_CheckTransaction_Test is AssetTransferRightsGuardTest {

}


/*----------------------------------------------------------*|
|*  # CHECK AFTER EXECUTION                                 *|
|*----------------------------------------------------------*/

contract AssetTransferRightsGuard_CheckAfterExecution_Test is AssetTransferRightsGuardTest {

	function test_shouldFail_whenExecutionSucceeded_whenInsufficinetTokenizedBalance() external {
		vm.mockCall(
			module,
			abi.encodeWithSignature("hasSufficientTokenizedBalance(address)", safe),
			abi.encode(false)
		);

		vm.expectRevert("Insufficient tokenized balance");
		vm.prank(safe);
		guard.checkAfterExecution(keccak256("how you doin?"), true);
	}

	function test_shouldPass_whenExecutionSucceeded_whenSufficinetTokenizedBalance() external {
		vm.mockCall(
			module,
			abi.encodeWithSignature("hasSufficientTokenizedBalance(address)", safe),
			abi.encode(true)
		);

		vm.prank(safe);
		guard.checkAfterExecution(keccak256("we were on a break!"), true);
	}

	function test_shouldNotCallATR_whenExecutionNotSucceeded() external {
		vm.mockCall(
			module,
			abi.encodeWithSignature("hasSufficientTokenizedBalance(address)", safe),
			abi.encode(false) // would fail if called
		);

		vm.prank(safe);
		guard.checkAfterExecution(keccak256("happy end"), false);
	}

}


/*----------------------------------------------------------*|
|*  # HAS OPERATOR FOR                                      *|
|*----------------------------------------------------------*/

contract AssetTransferRightsGuard_HasOperatorFor_Test is AssetTransferRightsGuardTest {

	function test_shouldReturnTrue_whenCollectionHasOperator() external {
		vm.mockCall(
			operators,
			abi.encodeWithSignature("hasOperatorFor(address,address)", safe, token),
			abi.encode(true)
		);

		bool hasOperator = guard.hasOperatorFor(safe, token);

		assertEq(hasOperator, true);
	}

	function test_shouldReturnTrue_whenERC777HasDefaultOperator() external {
		vm.mockCall(
			erc1820Registry,
			abi.encodeWithSignature("getInterfaceImplementer(address,bytes32)"),
			abi.encode(token)
		);

		address[] memory defaultOperators = new address[](1);
		defaultOperators[0] = alice;
		vm.mockCall(
			token,
			abi.encodeWithSignature("defaultOperators()"),
			abi.encode(defaultOperators)
		);
		vm.mockCall(
			token,
			abi.encodeWithSignature("isOperatorFor(address,address)", alice, safe),
			abi.encode(true)
		);

		bool hasOperator = guard.hasOperatorFor(safe, token);

		assertEq(hasOperator, true);
	}

	function test_shouldReturnFalse_whenCollectionHasNoOperator() external {
		vm.mockCall(
			operators,
			abi.encodeWithSignature("hasOperatorFor(address,address)", safe, token),
			abi.encode(false)
		);

		bool hasOperator = guard.hasOperatorFor(safe, token);

		assertEq(hasOperator, false);
	}

}
