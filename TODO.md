# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs


### Manager

* Serialize nodes on shutdown
* Broadcast system events:
    - `sys.node.added`
    - `sys.node.removed`
    - `sys.node.acked`
    - `sys.node.disabled`
    - `sys.startup`
    - `sys.shutdown`
    - `sys.reloaded`


### Observers

* Figure out how to match on delta events: how to specify the criteria for matching nodes vs. matching the changes in the delta?
* Re-subscribe on `sys.startup`, `sys.reloaded`, `sys.node.added`


### Nodes

* Allow expressing arbitrary, secondary dependencies between nodes (FTP under host X can't operate if LDAP under host N is down, etc)



## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

