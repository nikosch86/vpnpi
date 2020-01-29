# bootstrap a RaspberryPi to become a WiFi Hotspot prepared for VPN

dockerized standalone ansible deployment to prepare a RaspberryPi to become a WiFi Hotspot, based on nikosch86/ansible-docker.  

bootstrapping:  
`docker-compose run control-machine ansible-playbook -i <IP>, bootstrap.yml`  

configuration run:  
`
docker-compose run control-machine ansible-playbook -i <IP>, config.yml
`  
