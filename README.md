# Morsera Contracts

A `DeadManSwitch` can be added to Gnosis Safes to allow them to execute arbitrary transactions at some time in the future. 
This set time can be a specific timestamp, or it can be a timeout from the last Safe tx.

## Background

Currently there is no simple way for a Gnosis Safe to execute arbitrary transactions after a period of inactivity or at a set time in the future. This project provides a solution.

A Gnosis Safe Module is a contract that is authorized to make transactions on behalf of a Safe.

A Gnosis Safe Guard is a contract that is called prior to any Safe transaction that will revert if a transaction does not follow the guard's rules.

The `DeadManSwitch` contract is both a module and a guard. It must be a module in order to execute transactions on the Safe's behalf.
It must be a guard in order to keep track of the safe's last transaction timestamp.

## Running Tests

make sure you have the `RPC_URL` environment variable set to an appropriate RPC. The network must have safe contracts deployed to it.

`make fork-test`
