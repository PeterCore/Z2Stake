// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract AirDrop {
  using ECDSA for bytes32;
  using Math for uint256;
   IERC20 public airdropToken;
   uint256 public totalTokensWithdrawn;
   
   mapping (address => bool) public wasClaimed;
   uint256 public constant TOKENS_PER_CLAIM = 100 * 10**18;
   event TokensAirdropped(address indexed beneficiary);

   constructor(address _airdropToken)  {
        require(_airdropToken != address(0));
        airdropToken = IERC20(_airdropToken);
   }
   
       function withdrawTokens() public {
        require(msg.sender == tx.origin, "Require that message sender is tx-origin.");

        address beneficiary = msg.sender;

        require(!wasClaimed[beneficiary], "Already claimed!");
        wasClaimed[msg.sender] = true;

        bool status = airdropToken.transfer(beneficiary, TOKENS_PER_CLAIM);
        require(status, "Token transfer status is false.");

        (bool success, uint256 _total) = totalTokensWithdrawn.tryAdd(TOKENS_PER_CLAIM);
        if(success){
         totalTokensWithdrawn = _total;
        }
        emit TokensAirdropped(beneficiary);
    }

}
