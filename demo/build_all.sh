#!/bin/bash

CURRENT_DIR=$(cd $(dirname $0); pwd)

cd $CURRENT_DIR/../src/basic

DEMOS=$(ls)

echo $DEMOS

for DEMO in $DEMOS
do
    echo "DEMO $DEMO"
    cd ${DEMO} && make && cd ..
    cp ${DEMO}/*.bin $CURRENT_DIR/${DEMO}.bin 
done


