#!/bin/bash 
LRANK=$OMPI_COMM_WORLD_LOCAL_RANK
APP=$*
export CUDA_VISIBLE_DEVICES=$LRANK
$APP

