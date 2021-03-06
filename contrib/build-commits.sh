#!/bin/bash

# Author: AJ Meyer
# Date: August 2013

# This script can be used to sequentially build many bitfiles across a range of
# git commits. This is helpful for doing a binary search for functional or
# build errors introduced at an unknown time.

echo "Usage: $0 GIT-RANGE  (e.g. $0 97de5..HEAD)"
COMMITS=$(git log --oneline $1 | awk '{print $1;}')

echo operating on: $COMMITS

for commit in $COMMITS; do
    echo Building Commit: $commit

    echo Creating directory build-$commit
    rm -r build-$commit
    mkdir build-$commit

    echo cleaning...
    make clean >> ./build-$commit/out.log

    echo checking out $commit
    git checkout $commit  >> ./build-$commit/out.log

    echo cleaning...
    make clean >> ./build-$commit/out.log

    echo building... tail ./build-$commit/out.log to observe
    make >> ./build-$commit/out.log

    echo copying result to ./build-$commit
    cp -r build ./build-$commit
    
    echo Finished building $commit
done

echo Checking out master
git checkout master

echo Done!
