{% if pillar.firewalld_allowed_ports %}
public-ports:
  firewalld.present:
    - name: public
    - ports: {{ pillar.firewalld_allowed_ports }}
{% endif %}

{% if pillar.firewalld_allowed_services %}
public-services:
  firewalld.present:
    - name: public
    - services: {{ pillar.firewalld_allowed_services }}
{% endif %}
