# To-Do

## First Release (0.1)

* README, Tutorial, Setup docs


### Manager

* Broadcast system events:
    - `sys.node.added`
    - `sys.node.removed`
    - `sys.node.acked`
    - `sys.node.disabled`
    - `sys.startup`
    - `sys.shutdown`
    - `sys.reloaded`


### Observers

* Re-subscribe on `sys.startup`, `sys.reloaded`, `sys.node.added`


### Nodes

* Allow expressing arbitrary, secondary dependencies between nodes (FTP under host X can't operate if LDAP under host N is down, etc)



## Second Release (0.2)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

