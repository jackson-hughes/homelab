# Ansible

## Setup

Create python virtual environment:

    python3 -m venv venv

Activate virtual environment:

    source venv/bin/activate

Install dependencies:

    pip install -r requirements.txt

## Execution

To apply all:

    ansible-playbook --playbooks/site.yml

