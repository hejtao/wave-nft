// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface ILockable  {
    function lockTokens(uint256[] calldata tokenIds,uint256 lockTime) external;
    function unlockTokens(uint256[] calldata tokenIds) external;
    function isTokenLocked(uint256 tokenId) external view returns (bool);
}
