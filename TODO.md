# To-Do

## Manager

* Serialize nodes on shutdown
* Include a node's subscriptions in its serialized data
* Implement API for loading/reloading nodes for fsevents or
  LDAP changes. 
* Implement the system events (sys.acked, sys.reloaded, etc.)

## Tree API

* Modify operational attributes of a node

## Observers

* Figure out how to match on delta events: the criteria
  for matching nodes has to be separated from that which matches
  the delta pairs.

## Node

* Allow expressing arbitrary, secondary dependencies between nodes (FTP under host X can't operate if LDAP under host N is down, etc)

## Setup/Installation

* Add a CLI for generating a basic setup and then adding 
  nodes/monitors/observers to it.

