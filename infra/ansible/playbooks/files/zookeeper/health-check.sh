#!/bin/bash

echo "ruok" | timeout 2 nc -w 2 localhost 2181 | grep imok
