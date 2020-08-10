from __future__ import print_function
import cm_client
from cm_client.rest import ApiException
from collections import namedtuple
from pprint import pprint
import json
import time
import sys
from os import getenv

def wait(cmd, timeout=None):
    SYNCHRONOUS_COMMAND_ID = -1
    if cmd.id == SYNCHRONOUS_COMMAND_ID:
        return cmd

    SLEEP_SECS = 5
    if timeout is None:
        deadline = None
    else:
        deadline = time.time() + timeout

    try:
        cmd_api_instance = cm_client.CommandsResourceApi(api_client)
        while True:
            cmd = cmd_api_instance.read_command(long(cmd.id))
            pprint(cmd)
            if not cmd.active:
                return cmd

            if deadline is not None:
                now = time.time()
                if deadline < now:
                    return cmd
                else:
                    time.sleep(min(SLEEP_SECS, deadline - now))
            else:
                time.sleep(SLEEP_SECS)
    except ApiException as e:
        print("Exception when calling ClouderaManagerResourceApi->import_cluster_template: %s\n" % e)


cm_client.configuration.username = 'admin'
cm_client.configuration.password = 'admin'
api_client = cm_client.ApiClient("http://localhost:7180/api/v40")

cm_api = cm_client.ClouderaManagerResourceApi(api_client)

# accept trial licence
# to do - check if trail was started already...
cm_api.begin_trial()


# DEFAULT VALUES
KDC={
  "KDC_HOST"        : "YourHostname",
  "KDC_ADMIN_HOST"  : "YourHostname",
  "KDC_TYPE"        : "MIT KDC",
  "KRB_ENC_TYPES"   : "aes256-cts-hmac-sha1-96 aes128-cts-hmac-sha1-96 arcfour-hmac-md5r",
  "SECURITY_REALM"  : "CLOUDERA.COM"
}

KDC_PASSWORD = getenv("PASSWORD") or "BadPass#1"
KDC_USERNAME = getenv("KDC_USERNAME") or "cloudera-scm/admin@CLOUDERA.COM"

for key in KDC:
  KDC[key] = getenv(key) or KDC[key]

# Update Cloudera Manager config for KRB
body = cm_client.ApiConfigList()
body.items=[ cm_client.ApiConfig(name=item, value=KDC[item]) for item in KDC ]
# print ("------- Calling with: {}".format(body))
api_response = cm_api.update_config(message="KRB", body=body)

# Import KDC admin credentials
cmd = cm_api.import_admin_credentials(password=KDC_PASSWORD, username=KDC_USERNAME)
# print ("------- Calling KDC credentionals with: {}/{}".format(KDC_USERNAME,KDC_PASSWORD))
wait(cmd)


# Install CM Agent on host
with open ("/root/myRSAkey", "r") as f:
    key = f.read()

instargs = cm_client.ApiHostInstallArguments(
    host_names=['YourHostname'],
    user_name='root', 
    private_key=key, 
    cm_repo_url='https://archive.cloudera.com/cm7/7.1.1/', 
    java_install_strategy='NONE', 
    ssh_port=22, 
    passphrase='')

# print ("------- Calling install agent with: {}".format(instargs))
cmd = cm_api.host_install_command(body=instargs)
wait(cmd)


    
# create MGMT/CMS
mgmt_api = cm_client.MgmtServiceResourceApi(api_client)
api_service = cm_client.ApiService()

api_service.roles = [cm_client.ApiRole(type='SERVICEMONITOR'), 
    cm_client.ApiRole(type='HOSTMONITOR'), 
    cm_client.ApiRole(type='EVENTSERVER'),  
    cm_client.ApiRole(type='ALERTPUBLISHER')]

mgmt_api.auto_assign_roles() # needed?
mgmt_api.auto_configure()    # needed?
mgmt_api.setup_cms(body=api_service)
cmd = mgmt_api.start_command()
wait(cmd)



# create the cluster using the template
with open(sys.argv[1]) as f:
    json_str = f.read()

Response = namedtuple("Response", "data")
dst_cluster_template=api_client.deserialize(response=Response(json_str),response_type=cm_client.ApiClusterTemplate)
cmd = cm_api.import_cluster_template(add_repositories=True, body=dst_cluster_template)
wait(cmd)
