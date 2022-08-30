// SPDX-License-Identifier: LGPL-3.0-only
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

	function _checkTransaction(
		address to,
		bytes memory data
	) private {
		_checkTransaction(to, data, Enum.Operation.Call, 0, 0);
	}

	function _checkTransaction(
		address to,
		bytes memory data,
		Enum.Operation operation,
		uint256 safeTxGas,
		uint256 gasPrice
	) private {
		guard.checkTransaction(
			to, 0, data, operation, safeTxGas, 100, gasPrice, address(0), payable(0), "", address(0)
		);
	}

	function _mockNumberOfTokenizedAssets(uint256 number) private {
		vm.mockCall(
			module,
			abi.encodeWithSignature("numberOfTokenizedAssetsFromCollection(address,address)", safe, token),
			abi.encode(number)
		);
	}

	function _mockAllowance(uint256 allowance) private {
		vm.mockCall(
			token,
			abi.encodeWithSignature("allowance(address,address)", safe, alice),
			abi.encode(allowance)
		);
	}

	function _expectAdd() private {
		vm.expectCall(
			operators,
			abi.encodeWithSignature("add(address,address,address)", safe, token, alice)
		);
	}

	function _expectRemove() private {
		vm.expectCall(
			operators,
			abi.encodeWithSignature("remove(address,address,address)", safe, token, alice)
		);
	}


	// ---> Basic checks
	function test_shouldFail_whenSafeTxGasNotZero() external {
		vm.expectRevert("Safe tx gas has to be 0 for tx to revert in case of failure");
		vm.prank(safe);
		_checkTransaction(
			address(0xde57),
			abi.encode("bert, bert, bert"),
			Enum.Operation.Call,
			100,
			0
		);
	}

	function test_shouldFail_whenGasPriceNotZero() external {
		vm.expectRevert("Gas price has to be 0 for tx to revert in case of failure");
		vm.prank(safe);
		_checkTransaction(
			address(0xde57),
			abi.encode("bert, bert, bert"),
			Enum.Operation.Call,
			0,
			100
		);
	}

	function test_shouldFail_whenOperationIsDelegatecall() external {
		vm.expectRevert("Only call operations are allowed");
		vm.prank(safe);
		_checkTransaction(
			address(0xde57),
			abi.encode("bert, bert, bert"),
			Enum.Operation.DelegateCall,
			0,
			0
		);
	}
	// <--- Basic checks

	// ---> Self authorization calls
	function test_shouldFail_whenChangingGuard() external {
		vm.expectRevert("Cannot change ATR guard");
		vm.prank(safe);
		_checkTransaction(safe, abi.encodeWithSignature("setGuard(address)"));
	}

	function test_shouldFail_whenEnablingModule() external {
		vm.expectRevert("Cannot enable ATR module");
		vm.prank(safe);
		_checkTransaction(safe, abi.encodeWithSignature("enableModule(address)"));
	}

	function test_shouldFail_whenDisablingModule() external {
		vm.expectRevert("Cannot disable ATR module");
		vm.prank(safe);
		_checkTransaction(safe, abi.encodeWithSignature("disableModule(address,address)"));
	}

	function test_shouldFail_whenChangingFallbackHandler() external {
		vm.expectRevert("Cannot change fallback handler");
		vm.prank(safe);
		_checkTransaction(safe, abi.encodeWithSignature("setFallbackHandler(address)"));
	}
	// <--- Self authorization calls

	// ---> ERC20 approvals
	function test_shouldFail_onApprove_whenERC20Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approve(address,uint256)", alice, 100e18));
	}

	function test_shouldAddOperator_onApprove_whenAllowanceZero_whenAmountNonZero_whenERC20NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approve(address,uint256)", alice, 100e18));
	}

	function test_shouldRemoveOperator_onApprove_whenAllowanceNonZero_whenAmountZero_whenERC20NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(100);

		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approve(address,uint256)", alice, 0));
	}

	// TODO: Test when foundry implements `expectNoCall`
	// function test_shouldNotAddOperator_onApprove_whenAllowanceZero_whenAmountZero_whenERC20NotTokenized() external
	// function test_shouldNotRemoveOperator_onApprove_whenAllowanceNonZero_whenAmountNonZero_whenERC20NotTokenized() external

	function test_shouldFail_onIncreaseAllowance_whenERC20Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("increaseAllowance(address,uint256)", alice, 100e18));
	}

	function test_shouldAddOperator_onIncreaseAllowance_whenERC20NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("increaseAllowance(address,uint256)", alice, 100e18));
	}

	function test_shouldRemoveOperator_onDecreaseAllowance_whenERC20AllowanceLessOrEqThanAmount() external {
		_mockAllowance(90e18);

		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("decreaseAllowance(address,uint256)", alice, 100e18));
	}

	// TODO: Test when foundry implements `expectNoCall`
	// function test_shouldNotRemoveOperator_onDecreaseAllowance_whenERC20AllowanceMoreThanAmount() external
	// <--- ERC20 approvals

	// ---> ERC721/ERC1155 approvals
	function test_shouldFail_onSetApprovalForAll_whenERC721Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("setApprovalForAll(address,bool)", alice, true));
	}

	function test_shouldAddOperator_onSetApprovalForAll_whenApproval_whenERC721NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("setApprovalForAll(address,bool)", alice, true));
	}

	function test_shouldRemoveOperator_onSetApprovalForAll_whenNotApproval_whenERC721NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);

		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("setApprovalForAll(address,bool)", alice, false));
	}
	// <--- ERC721/ERC1155 approvals

	// ---> ERC777 approvals
	function test_shouldFail_onAuthorizeOperator_whenERC777Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("authorizeOperator(address)", alice));
	}

	function test_shouldAddOperator_onAuthorizeOperator_whenERC777NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("authorizeOperator(address)", alice));
	}

	function test_shouldRemoveOperator_onRevokeOperator() external {
		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("revokeOperator(address)", alice));
	}
	// <--- ERC777 approvals

	// ---> ERC1363 approvals
	function test_shouldFail_onApproveAndCall_whenERC1363Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256)", alice, 100e18));
	}

	function test_shouldAddOperator_onApproveAndCall_whenAllowanceZero_whenAmountNonZero_whenERC1363NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256)", alice, 100e18));
	}

	function test_shouldRemoveOperator_onApproveAndCall_whenAllowanceNonZero_whenAmountZero_whenERC1363NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(100);

		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256)", alice, 0));
	}

	// TODO: Test when foundry implements `expectNoCall`
	// function test_shouldNotAddOperator_onApproveAndCall_whenAllowanceZero_whenAmountZero_whenERC1363NotTokenized() external
	// function test_shouldNotRemoveOperator_onApproveAndCall_whenAllowanceNonZero_whenAmountNonZero_whenERC1363NotTokenized() external

	function test_shouldFail_onApproveAndCallWithBytes_whenERC1363Tokenized() external {
		_mockNumberOfTokenizedAssets(1);

		vm.expectRevert("Some asset from collection has transfer right token minted");
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", alice, 100e18, "I went to library to pee"));
	}

	function test_shouldAddOperator_onApproveAndCallWithBytes_whenAllowanceZero_whenAmountNonZero_whenERC1363NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(0);

		_expectAdd();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", alice, 100e18, "11 towel categories"));
	}

	function test_shouldRemoveOperator_onApproveAndCallWithBytes_whenAllowanceNonZero_whenAmountZero_whenERC1363NotTokenized() external {
		_mockNumberOfTokenizedAssets(0);
		_mockAllowance(100);

		_expectRemove();
		vm.prank(safe);
		_checkTransaction(token, abi.encodeWithSignature("approveAndCall(address,uint256,bytes)", alice, 0, "it was always purple?"));
	}

	// TODO: Test when foundry implements `expectNoCall`
	// function test_shouldNotAddOperator_onApproveAndCallWithBytes_whenAllowanceZero_whenAmountZero_whenERC1363NotTokenized() external
	// function test_shouldNotRemoveOperator_onApproveAndCallWithBytes_whenAllowanceNonZero_whenAmountNonZero_whenERC1363NotTokenized() external
	// <--- ERC1363 approvals

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
		guard.checkAfterExecution(keccak256("smelly cat, smelly cat"), false);
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
