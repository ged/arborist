# To-Do

## Second Release (0.2)

* README, Tutorial, Setup docs
* Performance/profiling examination


### Setup/Installation

* Add a CLI for generating a basic setup and then adding nodes/monitors/observers to it.
* Potential federation / referral for sibling managers

### Nodes

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

### Manager

* Add optional authentication support (ZAUTH)


