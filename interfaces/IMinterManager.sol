// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

interface IMinterManager {
    function isMinter(address account) external view returns (bool);
    function addMinter(address account) external;
    function removeMinter(address account) external;
}