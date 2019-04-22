#!/usr/bin/env bash
set -e

if [ "${TRAVIS}" != "true" ]; then
  TRAVIS_COMMIT="localtesting"
  TRAVIS_JOB_ID="$(echo $RANDOM)"
  TRAVIS_REPO_SLUG="firebase/firebase-tools"
fi

CWD="$(pwd)"
TARGET_FILE="${TRAVIS_COMMIT}-${TRAVIS_JOB_ID}.txt"

GOOGLE_APPLICATION_CREDENTIALS="${CWD}/scripts/creds-private.json"
if [ "${TRAVIS_REPO_SLUG}" == "firebase/firebase-tools" ]; then
  GOOGLE_APPLICATION_CREDENTIALS="${CWD}/scripts/creds-public.json"
fi
export GOOGLE_APPLICATION_CREDENTIALS

echo "Running in ${CWD}"
echo "Running with node: $(which node)"
echo "Running with npm: $(which npm)"
echo "Running with Application Creds: ${GOOGLE_APPLICATION_CREDENTIALS}"

echo "Target project: ${FBTOOLS_TARGET_PROJECT}"

echo "Initalizing some variables..."
DATE="$(date)"
FUNCTIONS=( \
  "dbAction" \
  "nested.dbAction" \
  "httpsAction" \
  "pubsubAction" \
  "gcsAction" \
  "pubsubScheduleAction" \
)
echo "Variables initalized..."

echo "Creating temp directory..."
TEMP_DIR="$(mktemp -d)"
echo "Created temp directory: ${TEMP_DIR}"

echo "Building and packaging firebase-tools..."
npm pack
FBT_PACKAGE="$(pwd)/$(ls *.tgz)"
echo "Built and packaged firebase-tools: ${FBT_PACKAGE}"

echo "Installing firebase-tools..."
npm install --global "${FBT_PACKAGE}"
echo "Installed firebase-tools: $(which firebase)"

echo "Initalizing temp directory..."
# Copy files into place.
cp -r "${CWD}"/scripts/test-project/* "${TEMP_DIR}"
cp "${CWD}"/scripts/assets/functions_to_test.js "${TEMP_DIR}"/functions/index.js
cd "${TEMP_DIR}"
# Run npm install in the functions directory.
cd functions
npm install
cd -
echo "Initalized temp directory."

echo "Pretest..."
echo "Removing functions... (${FUNCTIONS[@]})"
firebase functions:delete \
  --force \
  --project="${FBTOOLS_TARGET_PROJECT}" \
  ${FUNCTIONS[@]} || echo "Nothing to delete..."
echo "Done with Pretest."

echo "Deploying Functions..."
OUTPUT_FILE="$(mktemp)"
firebase deploy \
  --only=functions \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
echo "Checking to make sure the functions were deployed... ${OUTPUT_FILE}"
for fnName in "${FUNCTIONS[@]}"
do
  if [ "$fnName" == "nested.dbAction" ]
  then
    fnName="nested"
  fi
  echo "Looking for ${fnName}..."
  grep "\[${fnName}.*Successful create operation" "${OUTPUT_FILE}" || \
    (echo "Missing entry for ${fnName}" && exit 1)
done
echo "Deployed Functions."

echo "Updating Functions..."
OUTPUT_FILE="$(mktemp)"
firebase deploy \
  --only=functions \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
echo "Checking to make sure the functions were deployed... ${OUTPUT_FILE}"
for fnName in "${FUNCTIONS[@]}"
do
  if [ "$fnName" == "nested.dbAction" ]
  then
    fnName="nested"
  fi
  echo "Looking for ${fnName}..."
  grep "\[${fnName}.*Successful update operation" "${OUTPUT_FILE}"
done
echo "Updated Functions."

echo "Triggering dbAction..."
export DB_DATA="{\"foo\":\"$(date)\"}"
echo $DB_DATA
export DATA_UUID=$(echo "${DB_DATA}" | md5)
echo "Writing data..."
firebase database:set \
  "/input/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" \
  -y \
  --data "${DB_DATA}"
# Give the function a moment.
sleep 5
OUTPUT_FILE="$(mktemp)"
firebase database:get \
  "/output/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee ${OUTPUT_FILE}
grep -q "${DB_DATA}" "${OUTPUT_FILE}" || \
  (echo "Database did not return expected value." && exit 1)
echo "Triggered dbAction."

echo "Triggering nested.dbAction..."
export DB_DATA="{\"foo\":\"$(date)\"}"
export DATA_UUID=$(echo "${DB_DATA}" | md5)
echo "Writing data..."
firebase database:set \
  "/inputNested/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" \
  -y \
  --data "${DB_DATA}"
# Give the function a moment.
sleep 5
OUTPUT_FILE="$(mktemp)"
firebase database:get \
  "/output/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee ${OUTPUT_FILE}
grep -q "${DB_DATA}" "${OUTPUT_FILE}" || \
  (echo "Database did not return expected value." && exit 1)
echo "Triggered nested.dbAction."

echo "Triggering httpsAction..."
OUTPUT_FILE="$(mktemp)"
export DB_DATA="{\"foo\":\"$(date)\"}"
export DATA_UUID=$(echo "${DB_DATA}" | md5)
curl -X POST \
  --data "${DATA_UUID}" \
  "https://us-central1-${FBTOOLS_TARGET_PROJECT}.cloudfunctions.net/httpsAction" > "${OUTPUT_FILE}"
echo $OUTPUT_FILE
grep -q "${DATA_UUID}" "${OUTPUT_FILE}" || \
  (echo "HTTPS function did not return expected value." && exit 1)
echo "Triggered httpsAction."

echo "Triggering pubsubAction..."
OUTPUT_FILE="$(mktemp)"
DATA_UUID=$(date | md5)
MESSAGE_DATA="{\"uuid\":\"${DATA_UUID}\"}"
MESSAGE_64="$(echo $MESSAGE_DATA | base64)"
echo "${MESSAGE_DATA}"
gcloud pubsub topics publish topic1 \
  --message="${MESSAGE_DATA}" \
  --project="${FBTOOLS_TARGET_PROJECT}"
# Give the function a moment...
sleep 5
firebase database:get \
  "/output/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
grep -q "${DATA_UUID}" "${OUTPUT_FILE}" || \
  (echo "Database did not return expected value." && exit 1)
echo "Triggered pubsubAction."

echo "Triggering gcsAction..."
OUTPUT_FILE="$(mktemp)"
DATA_UUID="$(date | md5)"
DATA_FILE="$(mktemp)"
gsutil cp "${DATA_FILE}" "gs://${FBTOOLS_TARGET_PROJECT}.appspot.com/${DATA_UUID}"
sleep 5
firebase database:get \
  "/output/${DATA_UUID}" \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
grep -q "${DATA_UUID}" "${OUTPUT_FILE}" || \
  (echo "Database did not return expected value." && exit 1)
echo "Triggered gcsAction."

echo "Triggering pubsubScheduleAction..."
OUTPUT_FILE="$(mktemp)"
DATA_UUID=$(date | md5)
MESSAGE_DATA="{\"uuid\":\"${DATA_UUID}\"}"
MESSAGE_64="$(echo $MESSAGE_DATA | base64)"
gcloud functions call pubsubScheduleAction \
  --data="${MESSAGE_DATA}" \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
grep -q "true" "${OUTPUT_FILE}" || \
  (echo "Functions call did not return expected value." && exit 1)
echo "Triggered pubsubScheduleAction."

echo "Testing removing functions... (${FUNCTIONS[@]})"
firebase functions:delete \
  --force \
  --project="${FBTOOLS_TARGET_PROJECT}" \
  ${FUNCTIONS[@]}
echo "Tested removing functions."

echo "Testing deploying with a filter..."
OUTPUT_FILE="$(mktemp)"
firebase deploy \
  --only=functions:nested,functions:httpsAction \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
echo "Checking to make sure the functions were deployed... ${OUTPUT_FILE}"
for fnName in nested httpsAction
do
  echo "Looking for ${fnName}..."
  grep "\[${fnName}.*Successful create operation" "${OUTPUT_FILE}" || \
    (echo "Missing entry for ${fnName}" && exit 1)
done
echo "Tested deploying with a filter."

echo "Testing deleting with a filter..."
OUTPUT_FILE="$(mktemp)"
firebase functions:delete \
  nested \
  --project="${FBTOOLS_TARGET_PROJECT}" | tee "${OUTPUT_FILE}"
echo "Checking to make sure the functions were deployed... ${OUTPUT_FILE}"
grep "\[nested.*Successful create operation" "${OUTPUT_FILE}" || \
  (echo "Missing entry for ${fnName}" && exit 1)
done
echo "Tested deleting with a filter."
