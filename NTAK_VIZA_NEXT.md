# NTAK / VIZA — Rosa developer connection checklist

## NTAK

The official PMS test connection questionnaire asks for:
- applicant company name, tax number, address, representative
- technical contact name, role, email and phone
- manufacturer/distributor name
- PMS name and version
- PMS website
- public IP of the PMS test system
- planned test start date
- optional statement that the software is only for own use and not intended for sale
- optional request not to publish the software on the NTAK website

Rosa already has the public website: https://egercasarosa.com/ .

Do not invent the company/tax/contact/public-IP fields. Those must be supplied by the software manufacturer/operator.

## VIZA

Submit the official PMS–THF–VIZA test connection request. After acceptance, VIZA supplies the test environment, unique identifiers, the storage-forwarding module to integrate, and the exact validation test sequence.

## Rosa implementation boundary

Already implemented:
- durable NTAK/VIZA event outbox
- guest registration data storage
- ID-scanner ingestion API boundary
- VIZA registration event queueing
- government transport state/attempt tables
- preview payload generation

Still dependent on the official developer packages:
- NTAK SOAP/WSDL transport and digital-signature implementation against the current v9.09 WSDL package
- NTAK certificate/endpoint configuration and official message validation
- VIZA storage-forwarding module integration
- VIZA test endpoint and unique manufacturer/property identifiers

These should not be mocked as production-ready. Once the official test package is received, the remaining adapter work can be completed against the exact current interface and then validated with MTÜ.
