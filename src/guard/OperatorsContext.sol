// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.15;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/utils/structs/EnumerableSet.sol";


/**
 * @title Operators Context contract
 * @notice Contract responsible for tracking approved operators of asset collections per safe address.
 */
abstract contract OperatorsContext {
	using EnumerableSet for EnumerableSet.AddressSet;


	/*----------------------------------------------------------*|
	|*  # VARIABLES & CONSTANTS DEFINITIONS                     *|
	|*----------------------------------------------------------*/

	/**
	 * @notice Set of operators per asset address per safe.
	 * @dev Operator is any address that can transfer asset on behalf of an owner.
	 *      Could have an allowance (ERC20) or could be approved for all owned assets (ERC721/1155-setApprovalForAll).
	 *      Operator is not address approved to transfer concrete ERC721 asset. This approvals are not tracked.
	 *      safe address => collection address => set of operator addresses
	 */
	mapping (address => mapping (address => EnumerableSet.AddressSet)) internal operators;


	/*----------------------------------------------------------*|
	|*  # CONSTRUCTOR                                           *|
	|*----------------------------------------------------------*/

	constructor() {

	}


	/*----------------------------------------------------------*|
	|*  # SETTERS                                               *|
	|*----------------------------------------------------------*/

	/**
	 * @dev Add operator of an asset collection to a safe.
	 *      Address will not be duplicated if an operator is already in operators set.
	 * @param safe Address of a safe that is approving operator.
	 * @param asset Address of an asset collection that is approved.
	 * @param operator Address of an operator that is approved by safe for asset collection.
	 */
	function _addOperator(address safe, address asset, address operator) internal {
		operators[safe][asset].add(operator);
	}

	/**
	 * @dev Remove operator from operators set.
	 * @param safe Address of a safe that has approved operator.
	 * @param asset Address of an asset collection that has been approved.
	 * @param operator Address of an operator that has been approved by safe for asset collection.
	 */
	function _removeOperator(address safe, address asset, address operator) internal {
		operators[safe][asset].remove(operator);
	}


	/*----------------------------------------------------------*|
	|*  # GETTERS                                               *|
	|*----------------------------------------------------------*/

	/**
	 * @notice Check if safe has an operator for asset collection.
	 * @param safe Address of a safe that is checked for operator.
	 * @param asset Address of an asset collection that is checked for operator.
	 * @return True if safe has na operator for asset collection.
	 */
	function hasOperatorFor(address safe, address asset) public virtual view returns (bool) {
		return operators[safe][asset].length() > 0;
	}

	/**
	 * @notice Get list of all operators for given safe and asset address.
	 * @param safe Address of a safe that is checked for operator.
	 * @param asset Address of an asset collection that is checked for operator.
	 * @return List of recorded operators.
	 */
	function operatorsFor(address safe, address asset) external view returns (address[] memory) {
		return operators[safe][asset].values();
	}


	/*----------------------------------------------------------*|
	|*  # RECOVER                                               *|
	|*----------------------------------------------------------*/

	/**
	 * @notice Function that would resolve invalid approval state of an ERC20 asset.
	 * @dev Invalid approval state can happen when approved address transfers all approved assets from a safe.
	 *      Approved address will stay as operator, even though the allowance would be 0.
	 *      Transfer outside of a safe would not update operators set.
	 * @param safe Address of a safe that has invalid allowance.
	 * @param asset Address of an asset collectoin that has invalid allowance.
	 * @param operator Address of an operator that is wrongly stated as an operator to a collection in a safe.
	 */
	function resolveInvalidAllowance(address safe, address asset, address operator) external {
		uint256 allowance = IERC20(asset).allowance(safe, operator);
		if (allowance == 0) {
			operators[safe][asset].remove(operator);
		}
	}

}
