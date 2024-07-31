// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract Treasury {

    IERC20 public lpToken;
    address public system;

    modifier onlySystem() {
        require(msg.sender == system);
        _;
    }

    constructor(address _token) {
        lpToken = IERC20(_token);
        system = msg.sender;
    }

    function withdrawTo(address to, uint256 amount) external onlySystem {
        lpToken.transfer(to, amount);
    }
}