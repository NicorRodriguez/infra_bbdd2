## BBDD IaC

In order to the IaC to work properly you will need to have the folowing tools:
- A running local Kubernetes cluster
- Kubectl
- Terraform
- docker
- git

In case you are using Windows you will need to do some extra steps.

git clone https://github.com/IgnacioPerez98/backend_bbdd2.git
cd backend_bbdd2
docker build -t pencaucu_backend:latest .


git clone https://github.com/IgnacioPerez98/frontend_bbdd2.git
cd frontend_bbdd2
docker build -t pencaucu_frontend:latest .

### Now that you have the images built you may proceed.

  Once you have all the dependencies, in order to deploy the application you will need to run the following commands:
  - terraform init
  - terraform apply
 
Once all the code is deployed, you will have the application running, in order to access the application you should run this command:

kubectl port-forward svc/grafana 8081:3000 -n monitoring & \
kubectl port-forward svc/penca-ucu-frontend 8080 -n penca-ucu & \
kubectl port-forward svc/penca-ucu-backend 3000 -n penca-ucu

You can get an overview of the DB state going to localhost:8081 and for the frontend localhost:8080.
