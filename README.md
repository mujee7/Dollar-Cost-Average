
## Dollar Cost Average

This Project is basically a DCA smart contract and bot to perform transaction on usrs behalf after some time interval.

## Main contract
Main DCA contract is in src/contracts/DCA.sol
which have the core logic of the DCA

### Keeper
Keeper is the address that will perform transactions on users behalf after a time period.

just run the following command

node bot

It will starting listening to the blockchain events.


Before running bot make sure you add the keepers private key in .env



### Test

```shell
$ forge test
```

forge test --fork-url https://base-mainnet.g.alchemy.com/v2/YuO0fhrkSK-uPHnvE2rUTATsxKvCdaQq --fork-block-number 14171096 -vvv




#   D o l l a r - C o s t - A v e r a g e - D C A -  
 #   D o l l a r - C o s t - A v e r a g e - D C A -  
 #   D o l l a r - C o s t - A v e r a g e  
 