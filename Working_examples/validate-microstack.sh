echo 'servers'
microstack.openstack server list          # should show no servers
echo 'floating ips'
microstack.openstack floating ip list     # should show no floating IPs
echo 'networks -only external should show'
microstack.openstack network list         # only 'external' network may remain
echo 'routers'
microstack.openstack router list          # should show no routers
echo 'keypair'
microstack.openstack keypair list         # should be empty
echo 'project'
microstack.openstack project list         # demo project should be gone