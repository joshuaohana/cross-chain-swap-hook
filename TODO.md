TODO List for SwapHook Project

Wire Up a Bot to Call completeSwap
  already have the bot and it listens fine, just need to call complete

Test out scripts and see the bot call complete, print balances after

add whitelist and unit tests

build mega basic ui, connect wallet, do the swap (which does the pause and everything)
  show little explanation dealie in ui
  need extra event emits in swap I think?

no, done with single chain full workflow! onto the hard part

first step towards multi chain...
  1) have the bot CHECK and compare prices on another network
    a) that means I need to have scripts to deploy multiple chains with different liquidities and stuff
    b) okay
  2) start designing the single sided liquidity and what all that'll consist of...


- start keeping a running track of unsolved problems

"trusted bot"
rebalancing solver
liquidity fragmentation for LPs to withdraw

- start building demo materials, decks, presentations, etc


- plot out the rebalancer a bit, based on 24hr rolling volume move some balances around? or after big swaps?



,.,.. the story

So as Ethereum grows L2 liquidity fragmentation pricing differences
We rely on arbitrage bots to smooth out pricing and manage liquidity across L2s
But what if it could be done within Uniswap V4 pools themselves, enter... My Awesome Hook!

Deployed to any or all networks that Uniswap V4 is on, the Hook enables users to seamlessly capitalize on price differences between chains
No bridging or extra steps, swaps fall back to native chains when no better price is found
And now, instead of arbitrage bots capturing all that value, swappers themselves will!
As a bonus, a new opportunity for liquidity providers to fasciliate this by providing single sided pre-bridged liquidity

?? question
the price on the first chain doesn't actually change since no swap actually happened
what if... we use the pre-bridged funds and execute a reverse of the swap?
we "waste" gas and tx fees but then we actually DO move the price
hmm


--

Hook Idea Cross-Chain Auto-Arbitrage
Find and execute cross-chain swaps on alternate chains when more profitable, enabled with single-sided pre-bridged liquidity, quickly and with minimal user friction.

How it works;
Working with an off-chain trusted bot and ultimately an AVS like solution, the hook will find if the current chain nets the user the most return tokens, or if routing through an other supported chain is more profitable. Pre-bridged single-sided liquidity makes this possible, since no actual bridging needs to occur for the swap to fully execute. Liquidity providers can deposit single token pre-bridged liquidity and earn a share of the additional return when using cross chain swaps.

What makes it awesome;
Additional opportunities for liquidity providers who want to deposit a single token
Feels as fast as a regular swap, no need to wait for cross-chain bridging
Better returns for users
Helps balance pricing and volume between chains, strengthening ecosystem

Challenges;
Needs a custom router/UI and won't work with native Uniswap UI
AVS or similar for swaps and solver system for rebalancing are technically challenging

Team;
Solo