#!/bin/bash


while true; do
    read -p "*WARNING*: deploying the search indicies to algolia will incur costs, do you want to continue?" yn
    case $yn in
        [Yy]* ) echo "deploying search"; break;;
        [Nn]* ) break;;
        * ) echo "Please answer yes or no.";;
    esac
done


