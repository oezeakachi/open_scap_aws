import boto3
import xml.etree.ElementTree as ET

# Rest of the code...

scap_report = s3.get_object(Bucket=bucket_name, Key=file_key)

root = ET.fromstring(scap_report['Body'].read())

useSecurityHub = ssmClient.get_parameter(Name='/SCAPTesting/EnableSecurityHub')['Parameter']['Value']

testResult = root.find(".//{http://checklists.nist.gov/xccdf/1.2}TestResult")

if testId not in ignoreList:
    if(item.findtext('{http://checklists.nist.gov/xccdf/1.2}result') == "fail"):
        buildDynamoDBList(dynamoDbItems, instanceId, item, bucket_name, file_key)
        if useSecurityHub == "yes" and item.attrib.get("severity") in ["high","medium","low"]:
            buildSecurityHubFindingsList(securityHubFindings, root, instanceId, item, region, aws_account_id, testVersion, bucket_name, file_key)
        if(item.attrib.get("severity") == "high"):
            high+=1
        elif(item.attrib.get("severity") == "medium"):
            medium+=1
        elif(item.attrib.get("severity") == "low"):
            low+=1
        elif(item.attrib.get("severity") == "unknown"):
            unknown+=1


sendMetric(high, 'SCAP High Finding', instanceId)
sendMetric(medium, 'SCAP Medium Finding', instanceId)
sendMetric(low, 'SCAP Low Finding', instanceId)

def sendMetric(value, title, instanceId):
    cloudWatch.put_metric_data(
        Namespace='Compliance',
        MetricData=[
            {
                'MetricName': title,
                'Dimensions': [
                    {
                        'Name': 'InstanceId',
                        'Value': instanceId
                    },
                ],
                'Value': value
            }
        ]
    )

table = dynamodb.Table('SCAP_Scan_Results')
with table.batch_writer() as batch:
    for item in dynamoDbItems:
        batch.put_item(
            Item = item
        )

myfindings = securityHubFindings
try:
    findingsLeft = True
    startIndex = 0
    stopIndex = len(myfindings)

    # Loop through the findings sending 100 at a time to Security Hub
    while findingsLeft:
        stopIndex = startIndex + 100
        if stopIndex > len(securityHubFindings):
            stopIndex = len(securityHubFindings)
            findingsLeft = False
        else:
            stopIndex = 100
        myfindings = securityHubFindings[startIndex:stopIndex]
        # submit the finding to Security Hub
        result = securityHub.batch_import_findings(Findings = myfindings)
        startIndex = startIndex + 100

        # print results to CloudWatch
        print(result)
except Exception as e:
    print("An error has occurred saving to Security Hub: " + str(e))


