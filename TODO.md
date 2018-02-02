# To-Do

## Second Release (0.2)

* README, Tutorial, Setup docs
* Performance/profiling examination

### Command line

* Add a 'lint' check, to provide warnings for common misconfigurations
  * Host nodes without any addresses attached

### Manager

* Split #add_node up into adding and replacing, performing sanity checks for each.
* Detect and error on identifier duplication during Manager startup

### Nodes

* Allow 'address' host DSL to accept multiple addresses in one call
* Ask a node (via tree-api or otherwise) what nodes it affects (immediate children, secondary dependents)

### Observers

 * Action dependencies -- as an example, if an action sends an email, don't trigger if the email service is offline. Potential action "chains", ie: If the email service is down, use a separate out-of-band action that sends SMS.

### Monitors

* Add a one-shot runner command for development of monitors. Loads and runs a monitor one time, maybe with some output describing how often it'd run, what its skew is, etc. [will@laika]

* Add some default monitor types and utilities
  - ftp
  - imap
  - pop
  - smtp

* Redo the select loop of the UDP socket monitor to wait for them in parallel instead of in series.


## Third Release (0.3)

### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.

### Manager

* Potential federation / referral for sibling managers
* Add optional authentication support (ZAUTH)


