# get wallet 1 balance of token 0
cast call (token0 address) "balanceOf(address)(uint256)" (wallet address) --rpc-url http://localhost:8545
cast call 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://localhost:8545


Token0 deployed at: 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9
Token1 deployed at: 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9