#!/bin/zsh
set -eu
task_root="${0:A:h:h}"
cd "$task_root"
source "$task_root/scripts/environment.sh"
swift run "${task_spm_options[@]}" -j 4 StatsCoreChecks
