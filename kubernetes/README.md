
Check the AWS IAM User that will be used to connect to the EKS.
```bash
aws sts get-caller-identity
```

To connect to EKS (updates the local kubeconfig)
```bash
aws eks --region us-east-1 update-kubeconfig --name my-eks-cluster
```
Verify access
If you get nodes most likely you have admin privileges
```bash
kubectl get nodes
```

Verify readwrite access
```bash
kubectl auth can-i "*" "*" # if this returns yes, it means you have admin privileges
# kubectl auth can-i "*" "*" --all-namespacess
```

We need to add IAM roles and IAM users to the EKS cluster.

Service accounts, Users and RBAC groups

Map IAM user and IAM role to custom RBAC group