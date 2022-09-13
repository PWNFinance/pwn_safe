// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import "safe-contracts/proxies/GnosisSafeProxyFactory.sol";
import "safe-contracts/proxies/GnosisSafeProxy.sol";
import "safe-contracts/GnosisSafe.sol";

import "../../src/factory/PWNSafeFactory.sol";
import "../../src/guard/AssetTransferRightsGuard.sol";
import "../../src/guard/AssetTransferRightsGuardProxy.sol";
import "../../src/guard/OperatorsContext.sol";
import "../../src/handler/DefaultCallbackHandler.sol";
import "../../src/AssetTransferRights.sol";

import "../helpers/malicious/DelegatecallContract.sol";
import "../helpers/malicious/HackerWallet.sol";
import "../helpers/token/T20.sol";
import "../helpers/token/T721.sol";
import "../helpers/token/T1155.sol";


abstract contract UseCasesTest is Test {

	address constant admin = address(0x8ea42a3334E2AaB7d144990FDa6afE67a85E2a5c);
	address constant erc1820Registry = address(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
	GnosisSafe gnosisSafeSingleton;
	GnosisSafeProxyFactory gnosisSafeFactory;
	DefaultCallbackHandler gnosisFallbackHandler;

	address constant alice = address(0xa11ce);
	address constant bob = address(0xb0b);

	address immutable owner = address(0x1001);
	address immutable ownerOther = address(0x1002);

	AssetTransferRights atr;
	OperatorsContext operatorsContext;
	PWNSafeFactory factory;
	GnosisSafe safe;
	GnosisSafe safeOther;

	constructor() {
		// Mock ERC1820 Registry
		vm.etch(erc1820Registry, bytes("data"));
		vm.mockCall(
			erc1820Registry,
			abi.encodeWithSignature("getInterfaceImplementer(address,bytes32)"),
			abi.encode(address(0))
		);

		// Ethereum mainnet or Goerli testnet
		if (block.chainid == 5) {
			gnosisSafeSingleton = GnosisSafe(payable(0x3E5c63644E683549055b9Be8653de26E0B4CD36E));
			gnosisSafeFactory = GnosisSafeProxyFactory(0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2);
			// Custom deployment of `DefaultCallbackHandler`
			gnosisFallbackHandler = DefaultCallbackHandler(0xF97779f08Fa2f952eFb12F5827Ad95cE26fEF432);
		}
		// Local devnet
		else if (block.chainid == 31337) {
			gnosisSafeSingleton = new GnosisSafe();
			gnosisSafeFactory = new GnosisSafeProxyFactory();
			gnosisFallbackHandler = new DefaultCallbackHandler();
		}
	}

	function setUp() public virtual {
		_deployRealm();

		address[] memory owners = new address[](1);

		owners[0] = owner;
		safe = factory.deployProxy(owners, 1);

		owners[0] = ownerOther;
		safeOther = factory.deployProxy(owners, 1);
	}

	function _deployRealm() private {
		atr = new AssetTransferRights();

		// 2. Deploy ATR Guard logic
		AssetTransferRightsGuard guardLogic = new AssetTransferRightsGuard();

		// 3. Deploye ATR Guard proxy with ATR Guard logic
		AssetTransferRightsGuardProxy guardProxy = new AssetTransferRightsGuardProxy(
			address(guardLogic), admin
		);

		// 4. Deploy Operators Context
		operatorsContext = new OperatorsContext(address(guardProxy));

		// 5. Initialized ATR Guard proxy as ATR Guard
		AssetTransferRightsGuard(address(guardProxy)).initialize(address(atr), address(operatorsContext));

		// 6. Deploy PWNSafe factory
		factory = new PWNSafeFactory(
			address(gnosisSafeSingleton),
			address(gnosisSafeFactory),
			address(gnosisFallbackHandler),
			address(atr),
			address(guardProxy)
		);

		// 7. Set guard address to ATR contract
		atr.setAssetTransferRightsGuard(address(guardProxy));

		// 8. Set PWNSafe validator to ATR contract
		atr.setPWNSafeValidator(address(factory));
	}

	function _executeTx(
		GnosisSafe _safe,
		address to,
		bytes memory data
	) public payable returns (bool) {
		return _executeTx(
			_safe, to, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(0)
		);
	}

	function _executeTx(
		GnosisSafe _safe,
		address to,
		uint256 value,
		bytes memory data,
		Enum.Operation operation,
		uint256 safeTxGas,
		uint256 baseGas,
		uint256 gasPrice,
		address gasToken,
		address payable refundReceiver
	) public payable returns (bool) {
		address _owner;
		{
			// To prevent unnecessary duplication in passet arguments and vm.prank cheatcode
			if (_safe == safe)
				_owner = owner;
			else if (_safe == safeOther)
				_owner = ownerOther;
		}

		uint256 ownerValue;
		{
			ownerValue = uint256(uint160(_owner));
		}

		vm.prank(_owner);
		return _safe.execTransaction(
			to,
			value,
			data,
			operation,
			safeTxGas,
			baseGas,
			gasPrice,
			gasToken,
			refundReceiver,
			abi.encodePacked(ownerValue, bytes32(0), uint8(1))
		);
	}

}

/*----------------------------------------------------------*|
|*  # ERC20                                                 *|
|*----------------------------------------------------------*/

contract UseCases_ERC20_Test is UseCasesTest {

	T20 t20;

	function setUp() override public {
		super.setUp();

		t20 = new T20();
		atr.setIsWhitelisted(address(t20), true);
	}


	/**
	 * 1:  mint asset
	 * 2:  approve 1/3 to first address
	 * 3:  approve 1/3 to second address
	 * 4:  fail to mint ATR token for 1/3
	 * 5:  first address transfers asset
	 * 6:  resolve internal state
	 * 7:  fail to mint ATR token for 1/3
	 * 8:  set approvel of second address to 0
	 * 9:  mint ATR token for 1/3
	 * 10: fail to approve asset
	 */
	function test_UC_ERC20_1() external {
		// 1:
		t20.mint(address(safe), 900e18);

		// 2:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, alice, 300e18)
		);

		// 3:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, bob, 300e18)
		);

		// 4:
		vm.expectRevert("GS013"); // Some asset from collection has an approval
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC20, address(t20), 0, 300e18)
			)
		);

		// 5:
		vm.prank(alice);
		t20.transferFrom(address(safe), alice, 300e18);

		// 6:
		_executeTx(
			safe, address(operatorsContext),
			abi.encodeWithSelector(
				operatorsContext.resolveInvalidAllowance.selector,
				address(safe), address(t20), alice
			)
		);

		// 7:
		vm.expectRevert("GS013"); // Some asset from collection has an approval
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC20, address(t20), 0, 300e18)
			)
		);

		// 8:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, bob, 0)
		);

		// 9:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC20, address(t20), 0, 300e18)
			)
		);

		// 10:
		vm.expectRevert("Some asset from collection has transfer right token minted");
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, bob, 300e18)
		);
	}

	/**
	 * 1:  mint asset
	 * 2:  mint ATR token for 1/3
	 * 3:  fail to approve asset
	 * 4:  transfer ATR token to other wallet
	 * 5:  transfer asset via ATR token
	 * 6:  approve 1/3 to first address
	 * 7:  transfer ATR token back to wallet
	 * 8:  fail to transfer tokenized asset back via ATR token
	 * 9:  first address transfers asset
	 * 10: resolve internal state
	 * 11: transfer tokenized asset back via ATR token
	 */
	function test_UC_ERC20_2() external {
		// 1:
		t20.mint(address(safe), 900e18);

		// 2:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC20, address(t20), 0, 300e18)
			)
		);

		// 3:
		vm.expectRevert("Some asset from collection has transfer right token minted");
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, alice, 300e18)
		);

		// 4:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.transferFrom.selector,
				address(safe), address(safeOther), 1
			)
		);

		// 5:
		_executeTx(
			safeOther, address(atr),
			abi.encodeWithSelector(
				atr.claimAssetFrom.selector,
				address(safe), 1, false
			)
		);

		// 6:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.approve.selector, alice, 300e18)
		);

		// 7:
		_executeTx(
			safeOther, address(atr),
			abi.encodeWithSelector(
				atr.transferFrom.selector,
				address(safeOther), address(safe), 1
			)
		);

		// 8:
		vm.expectRevert("GS013"); // Receiver has approvals set for an asset
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.claimAssetFrom.selector,
				address(safeOther), 1, false
			)
		);

		// 9:
		vm.prank(alice);
		t20.transferFrom(address(safe), alice, 300e18);

		// 10:
		_executeTx(
			safe, address(operatorsContext),
			abi.encodeWithSelector(
				operatorsContext.resolveInvalidAllowance.selector,
				address(safe), address(t20), alice
			)
		);

		// 11:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.claimAssetFrom.selector,
				address(safeOther), 1, false
			)
		);
	}

	/**
	 * 1: mint asset
	 * 2: mint ATR token for 1/3
	 * 3: burn 1/2 of assets
	 * 4: fail to burn 1/2 of assets
	 * 5: burn ATR token for 1/3
	 * 6: burn 1/2 of assets
	 */
	function test_UC_ERC20_3() external {
		// 1:
		t20.mint(address(safe), 600e18);

		// 2:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC20, address(t20), 0, 200e18)
			)
		);

		// 3:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.burn.selector, address(safe), 300e18)
		);

		// 4:
		vm.expectRevert("Insufficient tokenized balance");
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.burn.selector, address(safe), 300e18)
		);

		// 5:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(atr.burnAssetTransferRightsToken.selector, 1)
		);

		// 6:
		_executeTx(
			safe, address(t20),
			abi.encodeWithSelector(t20.burn.selector, address(safe), 300e18)
		);
	}

}


/*----------------------------------------------------------*|
|*  # ERC721                                                *|
|*----------------------------------------------------------*/

contract UseCases_ERC721_Test is UseCasesTest {

	T721 t721;

	function setUp() override public {
		super.setUp();

		t721 = new T721();
		atr.setIsWhitelisted(address(t721), true);
	}


	/**
	 * 1:  mint asset 1
	 * 2:  approve asset 1 to first address
	 * 3:  mint asset 2
	 * 4:  mint asset 3
	 * 5:  mint ATR token for asset 2
	 * 6:  fail to mint ATR token for asset 1
	 * 7:  fail to approve asset 3
	 * 8:  set second address as wallets operator for ATR tokens
	 * 9:  second address transfers ATR token 1 to self
	 * 10: fail to transfer tokenized asset 2 via ATR token 1 to second address without burning ATR token
	 * 11: transfer tokenized asset 2 via ATR token 1 to second address and burn ATR token
	 * 12: approve asset 3 to first address
	 */
	function test_UC_ERC721_1() external {
		// 1:
		t721.mint(address(safe), 1);

		// 2:
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.approve.selector, alice, 1)
		);

		// 3:
		t721.mint(address(safe), 2);

		// 4:
		t721.mint(address(safe), 3);

		// 5:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 2, 1)
			)
		);

		// 6:
		vm.expectRevert("GS013"); // Asset has an approved address
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
			)
		);

		// 7:
		vm.expectRevert("Some asset from collection has transfer right token minted");
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.approve.selector, alice, 3)
		);

		// 8:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(atr.setApprovalForAll.selector, bob, true)
		);

		// 9:
		vm.prank(bob);
		atr.transferFrom(address(safe), bob, 1);

		// 10:
		vm.expectRevert("Attempting to transfer asset to non PWNSafe address");
		vm.prank(bob);
		atr.claimAssetFrom(payable(address(safe)), 1, false);

		// 11:
		vm.prank(bob);
		atr.claimAssetFrom(payable(address(safe)), 1, true);

		// 12:
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.approve.selector, alice, 3)
		);
	}

	/**
	 * 1:  mint asset id 1
	 * 2:  mint asset id 2
	 * 3:  set first address as wallet operator for asset
	 * 4:  fail to mint ATR token for asset id 1
	 * 5:  remove first address as wallet operator for asset
	 * 6:  mint ATR token 1 for asset id 1
	 * 7:  fail to set first address as wallet operator for asset
	 * 8:  transfer ATR token 1 to first address
	 * 9:  transfer tokenized asset id 1 to first address and burn ATR token
	 * 10: set first address as wallet operator for asset
	 */
	function test_UC_ERC721_2() external {
		// 1:
		t721.mint(address(safe), 1);

		// 2:
		t721.mint(address(safe), 2);

		// 3:
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.setApprovalForAll.selector, alice, true)
		);

		// 4:
		vm.expectRevert("GS013"); // Some asset from collection has an approval
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
			)
		);

		// 5:
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.setApprovalForAll.selector, alice, false)
		);

		// 6:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
			)
		);

		// 7:
		vm.expectRevert("Some asset from collection has transfer right token minted");
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.setApprovalForAll.selector, alice, true)
		);

		// 8:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(atr.transferFrom.selector, address(safe), alice, 1)
		);

		// 9:
		vm.prank(alice);
		atr.claimAssetFrom(payable(address(safe)), 1, true);

		// 10:
		_executeTx(
			safe, address(t721),
			abi.encodeWithSelector(t721.setApprovalForAll.selector, alice, true)
		);
	}

	/**
	 * 1:  deploy multisig safe
	 * 2:  mint asset id 1
	 * 3:  fail to mint ATR token with one owner
	 * 4:  sign tx by second owner
	 * 5:  mint ATR token with both owners signatures
	 */
	function test_UC_ERC721_3() external {
		uint256 owner1PK = 7;
		uint256 owner2PK = 8;
		address owner1 = vm.addr(owner1PK);
		address owner2 = vm.addr(owner2PK);

		address[] memory owners = new address[](2);
		owners[0] = owner1;
		owners[1] = owner2;

		// 1:
		safe = factory.deployProxy(owners, 2);

		// 2:
		t721.mint(address(safe), 1);

		// 3:
		vm.expectRevert("GS020");
		vm.prank(owner1);
		safe.execTransaction(
			address(atr),
			0,
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
			),
			Enum.Operation.Call,
			0,
			10,
			0,
			address(0),
			payable(0),
			abi.encodePacked(uint256(uint160(owner1)), bytes32(0), uint8(1))
		);

		// 4:
		bytes memory owner2Signature;
		{
			bytes32 txHash = safe.getTransactionHash(
				address(atr),
				0,
				abi.encodeWithSelector(
					atr.mintAssetTransferRightsToken.selector,
					MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
				),
				Enum.Operation.Call,
				0,
				10,
				0,
				address(0),
				payable(0),
				safe.nonce()
			);

			(uint8 v, bytes32 r, bytes32 s) = vm.sign(owner2PK, txHash);
			owner2Signature = abi.encodePacked(r, s, v);
		}

		// 5:
		vm.prank(owner1);
		safe.execTransaction(
			address(atr),
			0,
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 1, 1)
			),
			Enum.Operation.Call,
			0,
			10,
			0,
			address(0),
			payable(0),
			abi.encodePacked(uint256(uint160(owner1)), bytes32(0), uint8(1), owner2Signature)
		);
	}

	/**
	 * 1:  init hacker wallet
	 * 2:  deploy new safe with hacker wallet as owner
	 * 3:  mint asset id 42
	 * 4:  mint ATR token id 1
	 * 5:  transfer ATR token to alice
	 * 6:  fail to execute reentrancy hack
	 *     - reportInvalidTokenizedBalance(uint256) will fail with 'Insufficient tokenized balance'
	 */
	function test_UC_ERC721_4() external {
		// 1:
		HackerWallet hackerWallet = new HackerWallet();

		// 2:
		address[] memory owners = new address[](1);
		owners[0] = address(hackerWallet);
		safe = factory.deployProxy(owners, 1);

		// 3:
		t721.mint(address(safe), 42);

		// 4:
		vm.prank(address(hackerWallet));
		safe.execTransaction(
			address(atr), 0,
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC721, address(t721), 42, 1)
			),
			Enum.Operation.Call, 0, 0, 0, address(0), payable(0),
			abi.encodePacked(uint256(uint160(address(hackerWallet))), bytes32(0), uint8(1))
		);

		// 5:
		vm.prank(address(hackerWallet));
		safe.execTransaction(
			address(atr), 0,
			abi.encodeWithSelector(atr.transferFrom.selector, address(safe), alice, 1),
			Enum.Operation.Call, 0, 0, 0, address(0), payable(0),
			abi.encodePacked(uint256(uint160(address(hackerWallet))), bytes32(0), uint8(1))
		);

		// 6:
		hackerWallet.setupHack(address(atr), 1);

		vm.expectRevert("GS013"); // Insufficient tokenized balance
		vm.prank(address(hackerWallet));
		safe.execTransaction(
			address(t721), 0,
			abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(safe), address(hackerWallet), 42),
			Enum.Operation.Call, 0, 0, 0, address(0), payable(0),
			abi.encodePacked(uint256(uint160(address(hackerWallet))), bytes32(0), uint8(1))
		);

	}

}


/*----------------------------------------------------------*|
|*  # ERC1155                                               *|
|*----------------------------------------------------------*/

contract UseCases_ERC1155_Test is UseCasesTest {

	T1155 t1155;

	function setUp() override public {
		super.setUp();

		t1155 = new T1155();
		atr.setIsWhitelisted(address(t1155), true);
	}


	/**
	 * 1:  mint asset id 1 amount 600
	 * 2:  mint asset id 2 amount 100
	 * 3:  set first address as wallet operator for asset
	 * 4:  fail to mint ATR token for asset id 1 amount 600
	 * 5:  remove first address as wallet operator for asset
	 * 6:  mint ATR token 1 for asset id 1 amount 600
	 * 7:  fail to set first address as wallet operator for asset
	 * 8:  transfer ATR token 1 to first address
	 * 9:  transfer tokenized asset id 1 amount 600 to first address and burn ATR token
	 * 10: set first address as wallet operator for asset
	 */
	function test_UC_ERC1155_1() external {
		// 1:
		t1155.mint(address(safe), 1, 600);

		// 2:
		t1155.mint(address(safe), 2, 100);

		// 3:
		_executeTx(
			safe, address(t1155),
			abi.encodeWithSelector(t1155.setApprovalForAll.selector, alice, true)
		);

		// 4:
		vm.expectRevert("GS013"); // Some asset from collection has an approval
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC1155, address(t1155), 1, 600)
			)
		);

		// 5:
		_executeTx(
			safe, address(t1155),
			abi.encodeWithSelector(t1155.setApprovalForAll.selector, alice, false)
		);

		// 6:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC1155, address(t1155), 1, 600)
			)
		);

		// 7:
		vm.expectRevert("Some asset from collection has transfer right token minted");
		_executeTx(
			safe, address(t1155),
			abi.encodeWithSelector(t1155.setApprovalForAll.selector, alice, true)
		);

		// 8:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(atr.transferFrom.selector, address(safe), alice, 1)
		);

		// 9:
		vm.prank(alice);
		atr.claimAssetFrom(payable(address(safe)), 1, true);

		// 10:
		_executeTx(
			safe, address(t1155),
			abi.encodeWithSelector(t1155.setApprovalForAll.selector, alice, true)
		);
	}


	/**
	 * 1:  mint asset id 1 amount 600
	 * 2:  mint ATR token 1 for asset id 1 amount 600
	 * 3:  call malicious contract
	 * 4:  fail to transfer assets
	 */
	function test_UC_ERC1155_2() external {
		// 1:
		t1155.mint(address(safe), 1, 600);

		// 2:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC1155, address(t1155), 1, 600)
			)
		);

		// 3:
		DelegatecallContract delegatecallContract = new DelegatecallContract();
		_executeTx(
			safe, address(delegatecallContract),
			abi.encodeWithSignature(
				"perform(address,bytes)",
				address(t1155), abi.encodeWithSignature("setApprovalForAll(address,bool)", alice, true)
			)
		);

		// 4:
		vm.expectRevert("ERC1155: caller is not token owner nor approved");
		vm.prank(alice);
		t1155.safeTransferFrom(address(safe), alice, 1, 600, "");
	}

	/**
	 * 1:  mint asset id 1 amount 600
	 * 2:  mint ATR token 1 for asset id 1 amount 600
	 * 3:  transfer ATR token 1 to alice
	 * 4:  fail to transfer asset to bob
	 * 5:  grant bobs recipient permission to alice
	 * 6:  transfer asset from safe to bob via ATR token hold by alice
	 */
	function test_UC_ERC1155_3() external {
		// 1:
		t1155.mint(address(safe), 1, 600);

		// 2:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(
				atr.mintAssetTransferRightsToken.selector,
				MultiToken.Asset(MultiToken.Category.ERC1155, address(t1155), 1, 600)
			)
		);

		// 3:
		_executeTx(
			safe, address(atr),
			abi.encodeWithSelector(atr.transferFrom.selector, address(safe), alice, 1)
		);

		// 4:
		RecipientPermissionManager.RecipientPermission memory permission = RecipientPermissionManager.RecipientPermission(
			MultiToken.Category.ERC1155, address(t1155), 1, 600,
			bob, alice, 0, keccak256("nonce")
		);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(6, atr.recipientPermissionHash(permission));

		vm.expectRevert("Permission signer is not stated as recipient");
		vm.prank(alice);
		atr.transferAssetFrom(payable(address(safe)), 1, true, permission, abi.encodePacked(r, s, v));

		// 5:
		vm.prank(bob);
		atr.grantRecipientPermission(permission);

		// 6:
		vm.prank(alice);
		atr.transferAssetFrom(payable(address(safe)), 1, true, permission, "");
	}

}
