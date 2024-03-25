#!/bin/bash

git clone -b fairseq_v3 https://github.com/ngoyal2707/Megatron-LM.git
pip install six regex
pushd Megatron-LM
pip install -e .
popd

git clone https://github.com/facebookresearch/metaseq.git
pushd metaseq
python setup.py build_ext --inplace
pip install -e .
popd

git clone https://github.com/facebookresearch/fairscale.git
pushd fairscale
git checkout fixing_memory_issues_with_keeping_overlap
pip install .
popd

pip install boto3
