#!/bin/bash
####
# fputil.bash:
#
# Helpers to test via FP util
####
export FPUTIL_TARGETS="generate build build-uts check-all install build-all coverage"
export FPUTIL_DEPLOYS="${FPRIME_DIR}/Ref ${FPRIME_DIR}/RPI"

export INT_DEPLOYS="${FPRIME_DIR}/Ref"
####
# fputil_action:
#
# Runs an action for the FP util. This takes two parameters a target and a deployment. This assumes
# prequsite actions already exist.
# :param target($1): command to run with FP util
# :param deploy($2): deployment to run on
####
function fputil_action
do
    export TARGET="${1}"
    export WORKDIR="${2}"
    let JOBS="${JOBS:-$(( ( RANDOM % 100 )  + 1 ))}"
    (
        cd "${WORKDIR}"
        # Generate is only needed when it isn't being tested
        if [[ "${TARGET}" != "generate" ]]
        then
            echo "[INFO] Generating build cache before ${WORKDIR//\//_} '${TARGET}' execution"
            fprime-util "generate" --jobs "${JOBS}" > "${LOG_DIR}/${WORKDIR//\//_}_pregen.out.log" 2> "${LOG_DIR}/${WORKDIR//\//_}_pregen.err.log" \
                || fail_and_stop "Failed to generate before ${WORKDIR//\//_} '${TARGET}' execution"
        fi
        echo "[INFO] FP Util in ${WORKDIR} running ${target} with ${JOBS} jobs"
        fprime-util "${target}" --jobs "${JOBS}" > "${LOG_DIR}/${WORKDIR//\//_}_pregen.out.log" 2> "${LOG_DIR}/${WORKDIR//\//_}_pregen.err.log" \
            || fail_and_stop "Failed to run '${TARGET}' in ${WORKDIR}"
    ) || exit 1
done

####
# integration_test:
#
# Runs the FPrime GDS and integration test layer for a deployment.
# :param deploy($1): deployment to run on.
####
function integration_test
do
    let SLEEP_TIME=10
    export WORKDIR="${1}"
    fputil_action "${WORKDIR}" "install" || fail_and_stop "Failed to install before integration test"
    (
        mkdir -p "${LOG_DIR}/gds-logs"
        # Start the GDS layer and give it time to run
        echo "[INFO] Starting headless GDS layer"
        fprime-gds -d "${WORKDIR}" -g none -l "${LOG_DIR}/gds-logs" 1>${LOG_DIR}/gds-logs/fprime-gds.stdout.log 2>${LOG_DIR}/gds-logs/fprime-gds.stderr.log &
        GDS_PID=$!
        echo "[INFO] Allowing GDS ${SLEEP_TIME} seconds to start"
        sleep ${SLEEP_TIME}
        # Check the above started successfully
        ps -p ${GDS_PID} 2> /dev/null 1> /dev/null || fail_and_stop "Failed to start GDS layer headlessly"
        # Run integration tests
        (
            cd "${WORKDIR}"
            echo "[INFO] Running $1's pytest integration tests" 
            pytest "${LOG_DIR}/${WORKDIR//\//_}_pytest_ints.out.log" 2> "${LOG_DIR}/${WORKDIR//\//_}_pytest_ints.err.log"
        )
        RET_PYTEST=$?
        kill $GDS_PID
        sleep 2
        pkill -KILL Ref
        exit ${RET_PYTEST}
    ) || fail_and_stop "Failed integration tests on ${WORKDIR}"
done
