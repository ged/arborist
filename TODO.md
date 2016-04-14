# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs


### Manager

* Only restore timestamps from serialized node dependencies, not the deps themselves.

* Broadcast system events:
    - `sys.node.added`
    - `sys.node.removed`
    - `sys.startup`
    - `sys.shutdown`


* Add a 'depth' argument to the 'list' API.


### Observers

* Re-subscribe on `sys.startup`, `sys.reloaded`, `sys.node.added`
* Add `except` to observers DSL


### Nodes

* Allow a service node to not inherit all of its host's addresses (i.e., be bound to one address only or whatever)

### Monitor

* Add some default monitor types and utilities
  - UDP socket check
  - Basic monitors for stdlib Net::* protocols/services
  - 

* Gems for monitor types that have external dependency
  - SNMP

### Watch Command

* Re-subscribe on `sys.startup`, `sys.reloaded`, `sys.node.added`


## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

### Nodes

* Ask a node (via tree-api or otherwise) what nodes it affects (immediate children, secondary dependents)
