# To-Do

## Manager

* Serialize nodes on shutdown
* Include a node's subscriptions in its serialized data
* Implement loading/reloading nodes. 

## Tree API

* Add "grafting": node add/removal

## Observers

* Scheduling time periods for action/summarizing
* Summarizing and Actions should be 1st order objects
* Unsubscribe from Arborist and ZMQ subscriptions on shutdown
* Figure out how to match on delta events: the criteria
  for matching nodes has to be separated from that which matches
  the delta pairs.

## Node

