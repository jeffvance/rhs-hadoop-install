#!/bin/bash
#Taken from https://github.com/roofmonkey/ContinuousIntegration/blob/master/runtests.sh

ls -l
first_ls=$?

ls -la
second_ls=$?

if [[ $first_ls == 0 && $second_ls == 0 ]]; then
echo "Tests Passed ! "
      exit 0
fi

echo "Some of the Tests Failed exiting (1) first testresult = $first_ls , second test result = $second_ls "
exit 1
