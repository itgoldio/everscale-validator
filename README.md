**Table of contents**
- [Long instructions with detailed explanations](#long-instructions-with-detailed-explanations)
  - [Install Ansible](#install-ansible)
  - [Ubuntu and Debian](#ubuntu-and-debian)
  - [CentOS](#centos)
  - [Oracle Linux](#oracle-linux)
  - [Deploying node via this playbook](#deploying-node-via-this-playbook)
    - [Example for deploying on remote machine](#example-for-deploying-on-remote-machine)
  - [Variables](#variables)
  - [Usage](#usage)
  - [Upgrading node version](#upgrading-node-version)
  - [Deploy for custom network](#deploy-for-custom-network)
  - [Monitoring](#monitoring)
  - [StatsD metrics](#statsd-metrics)
  - [Alerting](#alerting)
  - [Automate staking through depool](#automate-staking-through-depool)
    - [Automate ticktock depool](#automate-ticktock-depool)
    - [Automate send validation request](#automate-send-validation-request)
    - [*[Optional]* Sign transaction use secondary key](#optional-sign-transaction-use-secondary-key)
  - [Scripts](#scripts)
  - [Support](#support)
  - [Changelog](#changelog)

**This ansible script is designed for deploying a rust-based everscale node on dedicated or virtual servers**

* Minimum OS versions:
Ubuntu: 18.04\
Debian: 10\
CentOS, Oracle Linux: 8

* Ansible version
This has been tested on Ansible 2.9.х

* Requirements
**This playbook requires root privileges or sudo**

Ansible ([What is Ansible](https://www.ansible.com/resources/videos/quick-start-video)?)

For validator in _mainnet_ you need about 128 GB RAM at least, 500 GB HDD and about 16 cores for comfortable driving

Validator on _RFLD-net_ needs about 32 GB RAM at least, 250 GB HDD and about 8 cores


---
## Very quick start for local install

1. Install `git` and  `ansible`
2. `git clone https://github.com/itgoldio/everscale-validator.git && cd everscale-validator`
3. Edit inventory file: `vim inventory`
4. Deploy `ansible-playbook deploy_ever_node.yml -c local -t basic`
5. Keys
* If you already have keys, put it to `/home/<username>/ton-keys`

generate pubKey:\
`tonos-cli -c /var/ton-work/rnode/configs/tonos-cli.conf.json genpubkey SEED-PHRASE`

`cd ~/scripts/`\
`./Prep-Msig.sh Tik Safe 1 0`\
`./Prep-Msig.sh $HOSTNAME Safe 1 -1`\
`./Prep-DePool.sh`

For participating in elections and validating, run script\
`./next_elect_set_time.sh`

This script set crontab

That's it! You got fresh validator! Graz!

* _If you preffer automatically deploy keys by scripts, start reading from_ [here](https://github.com/Custler/main.evs.dev#5-deploy-accounts)


# Long instructions with detailed explanations

## Install Ansible

[Install Ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html) to the managed machine

## Ubuntu and Debian

Ansible installation guide for Ubuntu: [read](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-ansible-on-ubuntu)

`sudo apt update`\
`sudo apt install ansible sshpass git python3 python3-pip`
`pip3 install jmespath`

## CentOS

Ansible installation guide for CentOS: [read](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html#installing-ansible-on-rhel-centos-or-fedora)

`sudo dnf install epel-release`\
`sudo dnf install ansible sshpass git python3 python3-pip`
`pip3 install jmespath`

## Oracle Linux

`sudo dnf install oracle-epel-release-el8`\
`sudo dnf install ansible sshpass git python3 python3-pip`
`pip3 install jmespath`

## Deploying node via this playbook

* Download or clone this repository\
`git clone https://github.com/itgoldio/everscale-validator`

* Go to the playbook directory\
`cd everscale-validator/`

* Edit the inventory file `inventory`

  Specify the IP addresses in `ever_node` and `monitoring_server` section and connection settings (`ansible_user`, `ansible_ssh_pass` ...) for your environment. 
  
  If you run the playbook **locally**, don't change the default settings.

### Example for deploying on remote machine

For example we have three servers:
* two for validator nodes
* one for monitoring

First server with enabled remote login for `root` and second host with non-root user `someuser` but with enabled `sudo` for this user

Edit inventory file:
`vim inventory`

`[ever_node]`\
`11.22.33.44 ansible_user='root' ansible_ssh_pass='secretpassword'`\
`22.33.44.55 ansible_user='someuser' ansible_ssh_pass='supersecretpassword' ansible_become=true`\
`[monitoring_server]`\
`33.44.55.66`

**There is no need to specify more than one monitoring server. All agents will connect only to the first one**

Edit the variable files vars/[ever_node.yml](./vars/ever_node.yml), vars/[system.yml](./vars/system.yml) and vars/[monitoring.yml](./vars/monitoring.yml)

`vim vars/ever_node.yml`\
`vim vars/system.yml`\
`vim vars/monitoring.yml`

**Be careful and don't forget to change standard passwords in [monitoring.yml](./vars/monitoring.yml) file**

* Run playbook:
  `ansible-playbook deploy_ever_node.yml`


* If you run playbook locally, use -c local parameter
  `ansible-playbook deploy_ever_node.yml -c local`


* To skip monitoring server installation role, specify '-t basic'
  `ansible-playbook deploy_ever_node.yml -c local -t basic`


---
## Variables

See the vars/[ever_node.yml](./vars/ever_node.yml), vars/[system.yml](./vars/system.yml) and vars/[monitoring.yml](./vars/monitoring.yml) files for more details

If you want use restoredb parameter in config, just uncomment `restoreDB: true` in vars/[ever_node.yml](./vars/ever_node.yml)

---
## Usage
By default, after deploying the everscale node it gets started automatically (change this behavior in vars/[ever_node.yml](./vars/ever_node.yml)).
You can control the running status of the everscale node using systemd commands:
`systemctl status ever-rnode`\
`systemctl stop ever-rnode` \
`systemctl start ever-rnode`

Everscale node stores logs in `/var/ton-work/rnode/logs` directory (change this by specifying **`ton_node_log_dir`** var in vars/[ever_node.yml](./vars/ever_node.yml)).
You can change log rules in file roles/ever_node_deploy/templates/[log_cfg.yml.j2](./roles/ever_node_deploy/templates/log_cfg.yml.j2)

Binary files located in `/usr/local/bin`, all other locations stored in vars/[ever_node.yml](./vars/ever_node.yml)


Monitoring services will start at the host specified in monitoring_server inventory section.
You can access Grafana the monitoring observability solution with pre-installed dashboards via a web-browser:\
`http://<monitoring_server_ip>:3000/`

Also you can access Chronograf - InfluxDB data observation tool - via a web-browser:\
`http://<monitoring_server_ip>:8888/`

## Upgrading node version

Upgrading for local installation:\
`ansible-playbook deploy_ever_node.yml -c local -t basic,genconfig`

For remote:\
`ansible-playbook deploy_ever_node.yml -t basic,genconfig`

---
## Deploy for custom network
When you changing global network config, for example, you running **net.ton.dev** network and want to change it to **rfld.ton.dev**

You should change `ever_node_config` variable in vars/[ever_node.yml](./vars/ever_node.yml) and run playbook again with tag 'flush' in addition with tag 'basic' for local installation:\
`ansible-playbook deploy_ever_node.yml -c local -t basic,flush`

For remote:\
`ansible-playbook deploy_ever_node.yml -t basic,flush`


If you only want update your current network global config or change node ports, use 'genconfig' tag.

For local installation:\
`ansible-playbook deploy_ever_node.yml -c local -t genconfig`

For remote:\
`ansible-playbook deploy_ever_node.yml -t genconfig`

**Do not use flush tag without any other tags**

---
## Monitoring

You can see installed grafana dashboard: `http://<monitoring_server_ip>:3000/`

![dashboard](docs/grafana-1.png?raw=true "grafana-1")

- Show current timediff and timediff graph
- Current Election state (Started/Stopped)
- Current Election start date (date or undefined value if election don’t started)
- Current Election end date (date or undefined value if election don’t started)
- Info that node already in validation participant list
- Info that node already won election and waits for new validation cyclee
- Count of unsigned transactions between wallet and depool
- Wallet balance
- Depool balance
- Proxy-1 balance
- Proxy-2 balance
- Many system graphs, we going to change it after rustcup will happen

You can see chronograf dashboard on next address `http://<monitoring_server_ip>:8888/`

![dashboard](docs/chronograf-1.png?raw=true "chronograf-1")

You can see or change credentials in vars/[monitoring.yml](./vars/monitoring.yml)

---
## StatsD metrics
We support builded in everscale rust node StatsD service. It is disabled by default, to turn it on change `ever_node_metrics_enabled` to True in vars/[ever_node.yml](./vars/ever_node.yml).

When you enable it you will able to use grafana dashboard:

![dashboard](docs/grafana-2.png?raw=true "grafana-2")

`http://<monitoring_server_ip>:3000/d/ton-3/freeton-statsd-metrics`

---
## Alerting
You can use grafana alerts for alerting

1. Create notification channel

Go to `http://<monitoring_server_ip>:3000/alerting/notifications` and create notification channel.
You can use telegram, slack, email, webhook and others
2. Create alert 
- Go to dashboard
- Edit dashboard panel
- select tab Alert

More info here: https://grafana.com/docs/grafana/latest/alerting/create-alerts/

---
## Automate staking through depool
You need to put your keys and data in `/home/<username>/ton-keys`:
- $HOSTNAME.addr file with wallet address
- depool.addr file with depool address
- msig.keys.json file with wallet private key
- *[Optional]* msig2.keys.json file with second sign private key
- tik.addr - send ticktock request to depool wallet addr. You can put $HOSTNAME.addr data to here
- tik.keys.json file with tik.addr private key

**TIP**: you can change keys default location in vars/[ever_node.yml](./vars/ever_node.yml) 

To automate validation process with scripts you should place it in cron
`crontab -e -u <username>`

### Automate ticktock depool
Add to cron\
`*/3 * * * * /bin/bash && export PATH=$PATH:/home/<username>/scripts &&  cd /home/<username>/scripts && ton-depool-ticktok.sh >> /var/ton-work/rnode/logs/crontab-ton-depool-ticktok.log`\
it will ticktock depool once in election cycle

### Automate send validation request
Add to cron\
`*/10 * * * * /bin/bash && export PATH=$PATH:/home/<username>/scripts &&  cd /home/<username>/scripts && ton-depool-validation-request.sh >> /var/ton-work/rnode/logs/crontab-ton-depool-validation-request.log`\
It will send validation request

### *[Optional]* Sign transaction use secondary key
If you use wallet with RegConfirm = 2, you can sign transaction with secondary wallet key to depool
To automate it, just add next string to cron\
`*/10 * * * * /bin/bash && export PATH=$PATH:/home/<username>/scripts &&  cd /home/<username>/scripts && ton-wallet-transaction-confirm.sh >> /var/ton-work/rnode/logs/crontab-ton-wallet-transaction-confirm.log`

---
## Scripts

All scripts will be added to PATH env for user. Monitoring agent use several scripts.
* [ton-env.sh](./roles/monitoring_agent/files/../templates/ton-env.j2)
Main script. It store all shared variables that used in other scripts. Please, fill it first.

* [rnode-monitoring.sh](./roles/monitoring_agent/files/scripts/rnode-monitoring.sh)
Main script for monitoring with icinga

These scripts are very usefull, but you need it only when not using scripts by Custler

* [ton-check-env.sh](./roles/monitoring_agent/files/scripts/ton-check-env.sh)\
Script system script. It check that ton-env.sh fill correct. Don't use it directly.

* [ton-depool-balance.sh](./roles/monitoring_agent/files/scripts/ton-depool-balance.sh)\
Script show depool balance in nanotokens.

* [ton-depool-proxy-1-balance.sh](./roles/monitoring_agent/files/scripts/ton-depool-proxy-1-balance.sh)\
Script show depool proxy 1 balance in nanotokens.

* [ton-depool-proxy-2-balance.sh](./roles/monitoring_agent/files/scripts/ton-depool-proxy-2-balance.sh)\
Script show depool proxy 2 balance in nanotokens.

* [ton-depool-ticktok.sh](./roles/monitoring_agent/files/scripts/ton-depool-ticktok.sh)\
Script send ticktock command from wallet to depool.

* [ton-depool-validation-request.sh](./roles/monitoring_agent/files/scripts/ton-depool-validation-request.sh)\
Validator script for elections through depool.

* [ton-election-date.sh](./roles/monitoring_agent/files/scripts/ton-election-date.sh)\
Script return date election in unix time or return 0 if election isn't active or return -1 is something wrong

* [ton-election-date-end.sh](./roles/monitoring_agent/files/scripts/ton-election-date-end.sh)\
Script return date end election in unix time or return -1 if election isn't active.

* [ton-election-date-start.sh](./roles/monitoring_agent/files/scripts/ton-election-date-start.sh)\
Script return date started election in unix time or return -1 if election isn't active.

* [ton-election-state.sh](./roles/monitoring_agent/files/scripts/ton-election-state.sh)\
Script return "ACTIVE" if elecetion is active or "STOPPED" otherwise

* [ton-node-diff.sh](./roles/monitoring_agent/files/scripts/ton-node-diff.sh)\
Script return time diff in unix time for local node or "-1" if console or node doesn't work

* [ton-node-participant-state.sh](./roles/monitoring_agent/files/scripts/ton-node-participant-state.sh)\
Script return "ACTIVE" if node already in participants list. It return "NOT_FOUND" if election is active, but node absent in participants list. Script return "UNKNOWN" if election stopped.

* [ton-wallet-balance.sh](./roles/monitoring_agent/files/scripts/ton-wallet-balance.sh)\
Script show wallet balance in nanotokens.

* [ton-ticktok-balance.sh](./roles/monitoring_agent/files/scripts/ton-ticktok-balance.sh)\
Script show tick account balance in nanotokens.

* [ton-wallet-transaction-confirm.sh](./roles/monitoring_agent/files/scripts/ton-wallet-transaction-confirm.sh)\
Script find unsigned transaction from wallet to depool and signet it use secondary key. It use ton-env.sh vars by default. You can send wallet addr and depool addr directly as arguments.

* [ton-wallet-transaction-count.sh](./roles/monitoring_agent/files/scripts/ton-wallet-transaction-count.sh)\
Script show count unsigned transaction from wallet to depool.

* [ton-node-validate-current.sh](./roles/monitoring_agent/files/scripts/ton-node-validate-current.sh)\
Script return info about current validation state.
  - Unknown - something wrong (node not working and etc)
  - True - node can validate at this time
  - False - node can't validate at this time

* [ton-node-validate-next.sh](./roles/monitoring_agent/files/scripts/ton-node-validate-next.sh)\
Script return info about next validation round.
  - Unknown - something wrong (node not working and etc)
  - True - node can validate in next round
  - False - node can't validate in next round


## Support
We can help you in telegram chats
- [Russian](https://t.me/itgoldio_support_ru)
- [English](https://t.me/tgoldio_support_en)

## Changelog
Here: [changelog.md](./changelog.md)
