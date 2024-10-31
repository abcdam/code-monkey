import os
import yaml
os.system('rsync -hvrP /tmp/.ollama /root/') # sync default ollama confs if necessary

conf_path = '/tmp/models.yaml'
os.system('ollama serve & sleep 1') # short breather to make sure ollama is ready to pull changes
with open(conf_path, 'r') as f:
    conf = yaml.safe_load(f)
for model_family in list(conf.keys()):
    for model_id in list(conf[model_family].keys()):
        os.system(f'ollama pull {model_family}:{model_id}')

os.system('kill $(pidof ollama)') # let openwebui handle the start
os.system('bash start.sh')

