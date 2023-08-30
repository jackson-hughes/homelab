{% if pillar.firewalld_allowed_ports %}
public:
  firewalld.present:
    - ports: {{ firewalld_allowed_ports }}
{% endfor %}

{% if pillar.firewalld_allowed_services %}
public:
  firewalld.present:
    - services: {{ firewalld_allowed_services }}
{% endfor %}
