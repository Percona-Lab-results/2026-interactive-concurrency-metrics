#!/bin/bash

# --- PREPARE pt-mysql-summary ---
if [ ! -f ./pt-mysql-summary ]; then
    wget http://percona.com/get/pt-mysql-summary 
    chmod +x pt-mysql-summary
fi