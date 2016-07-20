# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs

* Performance/profiling examination


### Manager



### Observers

* Destroy subscriptions on `sys.shutdown`
* Re-subscribe on `sys.startup`, `sys.node.added`
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

* Destroy subscriptions on `sys.shutdown`
* Re-subscribe on `sys.startup`, `sys.node.added`


## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

### Nodes

* Ask a node (via tree-api or otherwise) what nodes it affects (immediate children, secondary dependents)

### Observers

 * Action dependencies -- as an example, if an action sends an email,
   don't trigger if the email service is offline.  Potential action
   "chains", ie:  If the email service is down, use a separate
   out-of-band action that sends SMS.
