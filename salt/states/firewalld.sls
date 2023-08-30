{% if pillar.firewalld_allowed_ports %}
public:
  firewalld.present:
    - ports: {{ pillar.firewalld_allowed_ports }}
{% endif %}

{% if pillar.firewalld_allowed_services %}
public:
  firewalld.present:
    - services: {{ pillar.firewalld_allowed_services }}
{% endif %}
