# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```



创建 LoanLibrary 合约，将示例代码粘贴进 remix，无需部署
示例代码
将 HackQuestToken 合约的地址作为 LoanSystem 构造函数的参数， _UNLOCKEDRATE 取100，部署 LoanSystem
示例代码
：查询 LoanSystem 合约中 lpToken 和 treasury6：在 HackQuestToken 中调用 approve 函数，spender 取 LoanSystem 的地址， amount 取200。使用 balanceOf 查询当前用户以及 treasury（5中查出来的地址）的值7：在 LoanSystem 中使用 balanceOf 查询当前用户的值，然后调用 deposit 传入参数100，再次使用 balanceOf 查询当前用户的值。8：在 HackQuestToken 合约 中使用 balanceOf 查询当前用户以及 treasury 的值