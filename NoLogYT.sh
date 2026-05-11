#!/bin/bash

BLACK_TEXT=$'\033[0;90m'
RED_TEXT=$'\033[0;91m'
GREEN_TEXT=$'\033[0;92m'
YELLOW_TEXT=$'\033[0;93m'
BLUE_TEXT=$'\033[0;94m'
MAGENTA_TEXT=$'\033[0;95m'
CYAN_TEXT=$'\033[0;96m'
WHITE_TEXT=$'\033[0;97m'
TEAL=$'\033[38;5;50m'

BOLD_TEXT=$'\033[1m'
UNDERLINE_TEXT=$'\033[4m'
BLINK_TEXT=$'\033[5m'
NO_COLOR=$'\033[0m'
RESET_FORMAT=$'\033[0m'
REVERSE_TEXT=$'\033[7m'

clear

echo
echo "${CYAN_TEXT}${BOLD_TEXT}╔══════════════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ███╗   ██╗ ██████╗ ██╗      ██████╗  ██████╗             ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ████╗  ██║██╔═══██╗██║     ██╔═══██╗██╔════╝             ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ██╔██╗ ██║██║   ██║██║     ██║   ██║██║  ███╗            ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ██║╚██╗██║██║   ██║██║     ██║   ██║██║   ██║            ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ██║ ╚████║╚██████╔╝███████╗╚██████╔╝╚██████╔╝            ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝            ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║            Google Cloud Arcade Lab — Initializing...             ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╠══════════════════════════════════════════════════════════════════╣${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║  YT  ›  https://www.youtube.com/@NoLogYT                        ║${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}║  TG  ›  https://t.me/NoLogYT                                    ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╚══════════════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo

sleep 1

REGION=$(gcloud config get-value dataplex/region 2>/dev/null)

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
    REGION=$(gcloud config get-value compute/region 2>/dev/null)
fi

if [[ -z "$REGION" || "$REGION" == "(unset)" ]]; then
    echo "${YELLOW_TEXT}[!] region not found in config.${RESET_FORMAT}"
    read -rp "$(echo -e "${CYAN_TEXT}[>] input region: ${RESET_FORMAT}")" REGION
fi

echo "${GREEN_TEXT}[✓] region locked in »${RESET_FORMAT} ${WHITE_TEXT}${REGION}${RESET_FORMAT}"

PROJECT_ID=$(gcloud config get-value project 2>/dev/null)

if [[ -z "$PROJECT_ID" ]]; then
    echo "${RED_TEXT}[✗] no project id detected. aborting.${RESET_FORMAT}"
    exit 1
fi

echo "${GREEN_TEXT}[✓] project identified »${RESET_FORMAT} ${WHITE_TEXT}${PROJECT_ID}${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] enabling apis...${RESET_FORMAT}"

gcloud services enable \
dataplex.googleapis.com \
dataproc.googleapis.com \
bigquery.googleapis.com \
storage.googleapis.com \
--quiet

echo "${GREEN_TEXT}[✓] apis activated. all systems go.${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] deploying dataplex lake...${RESET_FORMAT}"

gcloud dataplex lakes create ecommerce-lake \
--location="${REGION}" \
--display-name="Ecommerce Lake" \
--quiet

echo "${GREEN_TEXT}[✓] lake is live. standing by for activation...${RESET_FORMAT}"
sleep 25

echo
echo "${YELLOW_TEXT}[~] creating zone...${RESET_FORMAT}"

gcloud dataplex zones create customer-contact-raw-zone \
--location="${REGION}" \
--lake=ecommerce-lake \
--display-name="Customer Contact Raw Zone" \
--type=RAW \
--resource-location-type=SINGLE_REGION \
--quiet

echo "${GREEN_TEXT}[✓] zone initialized. waiting for it to stabilize...${RESET_FORMAT}"
sleep 35

echo
echo "${YELLOW_TEXT}[~] attaching bigquery asset...${RESET_FORMAT}"

gcloud dataplex assets create contact-info \
--location="${REGION}" \
--lake=ecommerce-lake \
--zone=customer-contact-raw-zone \
--resource-type=BIGQUERY_DATASET \
--resource-name="projects/${PROJECT_ID}/datasets/customers" \
--display-name="Contact Info" \
--quiet

echo "${GREEN_TEXT}[✓] asset deployed. pipeline is taking shape.${RESET_FORMAT}"

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}╔══════════════════════════════════════════╗${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}║      MANUAL STEP — TASK 2 REQUIRED       ║${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}╚══════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}[>] open bigquery console and execute this query:${RESET_FORMAT}"
echo
echo "${GREEN_TEXT}    SELECT * FROM \`${PROJECT_ID}.customers.contact_info\`${RESET_FORMAT}"
echo "${GREEN_TEXT}    ORDER BY id${RESET_FORMAT}"
echo "${GREEN_TEXT}    LIMIT 50;${RESET_FORMAT}"
echo
read -rp "$(echo -e "${YELLOW_TEXT}[>] task 2 done? hit ENTER to continue...${RESET_FORMAT}")"
echo "${GREEN_TEXT}[✓] task 2 cleared. moving forward.${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] writing yaml spec file...${RESET_FORMAT}"

cat > dq-customer-raw-data.yaml <<EOF
rules:
- nonNullExpectation: {}
  column: id
  dimension: COMPLETENESS
  threshold: 1

- regexExpectation:
    regex: '^[^@]+[@]{1}[^@]+$'
  column: email
  dimension: CONFORMANCE
  ignoreNull: true
  threshold: .85

postScanActions:
  bigqueryExport:
    resultsTable: projects/${PROJECT_ID}/datasets/customers_dq_dataset/tables/dq_results
EOF

echo "${GREEN_TEXT}[✓] yaml spec written to disk.${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] scanning for storage bucket...${RESET_FORMAT}"

BUCKET_NAME="${PROJECT_ID}-bucket"

gsutil ls "gs://${BUCKET_NAME}" >/dev/null 2>&1

if [[ $? -ne 0 ]]; then
    echo "${YELLOW_TEXT}[!] bucket not found. provisioning now...${RESET_FORMAT}"
    gsutil mb -l "${REGION}" "gs://${BUCKET_NAME}"
fi

echo "${GREEN_TEXT}[✓] bucket online »${RESET_FORMAT} ${WHITE_TEXT}${BUCKET_NAME}${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] uploading yaml spec to bucket...${RESET_FORMAT}"

gsutil cp dq-customer-raw-data.yaml "gs://${BUCKET_NAME}/"

echo "${GREEN_TEXT}[✓] spec uploaded. remote copy confirmed.${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] initializing data quality scan...${RESET_FORMAT}"

gcloud dataplex datascans create data-quality customer-orders-data-quality-job \
--project="${PROJECT_ID}" \
--location="${REGION}" \
--data-source-resource="//bigquery.googleapis.com/projects/${PROJECT_ID}/datasets/customers/tables/contact_info" \
--data-quality-spec-file="gs://${BUCKET_NAME}/dq-customer-raw-data.yaml" \
--quiet

echo "${GREEN_TEXT}[✓] scan job created and registered.${RESET_FORMAT}"

echo
echo "${YELLOW_TEXT}[~] triggering scan execution...${RESET_FORMAT}"

gcloud dataplex datascans run customer-orders-data-quality-job \
--location="${REGION}"

echo "${GREEN_TEXT}[✓] scan is running. letting it process...${RESET_FORMAT}"
sleep 60

echo
echo "${YELLOW_TEXT}[~] pulling scan job list...${RESET_FORMAT}"

gcloud dataplex datascans jobs list \
--datascan=customer-orders-data-quality-job \
--location="${REGION}"

echo "${GREEN_TEXT}[✓] job list retrieved.${RESET_FORMAT}"

echo
echo "${MAGENTA_TEXT}${BOLD_TEXT}╔══════════════════════════════════════════╗${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}║      MANUAL STEP — TASK 6 REQUIRED       ║${RESET_FORMAT}"
echo "${MAGENTA_TEXT}${BOLD_TEXT}╚══════════════════════════════════════════╝${RESET_FORMAT}"
echo
echo "${CYAN_TEXT}[>] back to bigquery console. follow these steps:${RESET_FORMAT}"
echo
echo "${WHITE_TEXT}  1.${RESET_FORMAT}  open dataset   ${GREEN_TEXT}customers_dq_dataset${RESET_FORMAT}"
echo "${WHITE_TEXT}  2.${RESET_FORMAT}  open table     ${GREEN_TEXT}dq_results${RESET_FORMAT}"
echo "${WHITE_TEXT}  3.${RESET_FORMAT}  click tab      ${GREEN_TEXT}Preview${RESET_FORMAT}"
echo "${WHITE_TEXT}  4.${RESET_FORMAT}  copy first     ${GREEN_TEXT}rule_failed_records_query${RESET_FORMAT}"
echo "${WHITE_TEXT}  5.${RESET_FORMAT}  open new sql tab, paste and run"
echo "${WHITE_TEXT}  6.${RESET_FORMAT}  repeat for the second query"
echo
read -rp "$(echo -e "${YELLOW_TEXT}[>] task 6 done? hit ENTER to finish...${RESET_FORMAT}")"
echo "${GREEN_TEXT}[✓] task 6 cleared. that is the last one.${RESET_FORMAT}"

echo
echo "${CYAN_TEXT}${BOLD_TEXT}╔══════════════════════════════════════════════════════════════════╗${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║             [✓]  LAB COMPLETE — ACCESS GRANTED.                 ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╠══════════════════════════════════════════════════════════════════╣${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║        if this saved you time, support the channel:              ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${GREEN_TEXT}${BOLD_TEXT}║  YT  ›  https://www.youtube.com/@NoLogYT                        ║${RESET_FORMAT}"
echo "${BLUE_TEXT}${BOLD_TEXT}║  TG  ›  https://t.me/NoLogYT                                    ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║          like. subscribe. no log. just results.                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}║                                                                  ║${RESET_FORMAT}"
echo "${CYAN_TEXT}${BOLD_TEXT}╚══════════════════════════════════════════════════════════════════╝${RESET_FORMAT}"
echo
