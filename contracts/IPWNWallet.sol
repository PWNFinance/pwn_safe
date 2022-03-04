// SPDX-License-Identifier: None
pragma solidity 0.8.9;

interface IPWNWallet {
	function willReceiveTokenizedAsset(address tokenAddress, uint256 atrTokenId) external;
	function hasOperatorsFor(address tokenAddress) external returns (bool);
}
