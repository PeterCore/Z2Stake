//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
interface IAdmin {
    function isAdmin(address user) external view returns (bool);
}