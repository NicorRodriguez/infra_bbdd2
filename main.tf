provider "kubernetes" {
  config_path = "${pathexpand("~/.kube/config")}"
}

provider "helm" {
  kubernetes {
    config_path = "${pathexpand("~/.kube/config")}"
  }
}

# resource "null_resource" "build_backend" {
#   provisioner "local-exec" {
#     command = <<EOT
#       # Clean up the directory if it exists
#       rm -rf backend_bbdd2

#       # Clone the repository
#       git clone https://github.com/IgnacioPerez98/backend_bbdd2.git

#       # Navigate into the cloned directory
#       cd backend_bbdd2

#       # Build the Docker image
#       docker build -t pencaucu_backend:latest .

#       # Push the Docker image to the registry
#       docker push pencaucu_backend:latest
#     EOT
#     on_failure = "continue"
#   }
# }

# resource "null_resource" "build_frontend" {
#   provisioner "local-exec" {
#     command = <<EOT
#       # Clean up the directory if it exists
#       rm -rf frontend_bbdd2

#       # Clone the repository
#       git clone https://github.com/IgnacioPerez98/frontend_bbdd2.git

#       # Navigate into the cloned directory
#       cd frontend_bbdd2

#       # Build the Docker image
#       docker build -t pencaucu_frontend:latest .

#       # Push the Docker image to the registry
#       docker push pencaucu_frontend:latest
#     EOT
#     on_failure = "continue"
#   }
# }

resource "kubernetes_namespace" "monitoring" {

  metadata {
    name = "monitoring"
  }
}

resource "helm_release" "prometheus_operator" {
  depends_on = [kubernetes_namespace.monitoring]

  name       = "prometheus-operator"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    <<EOF
    alertmanager:
      enabled: true
    prometheus:
      enabled: true
      prometheusSpec:
        serviceMonitorSelector:
          matchLabels:
            release: prometheus-operator
    grafana:
      enabled: false
    EOF
  ]
}

resource "helm_release" "grafana" {
  depends_on = [helm_release.prometheus_operator]

  name       = "grafana"
  repository = "https://grafana.github.io/helm-charts"
  chart      = "grafana"
  namespace  = kubernetes_namespace.monitoring.metadata[0].name

  values = [
    <<EOF
    adminPassword: "admin"
    sidecar:
      dashboards:
        enabled: true
        label: grafana_dashboard
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
        - name: Prometheus
          type: prometheus
          access: proxy
          url: http://prometheus-operator-kube-p-prometheus.monitoring.svc.cluster.local:9090
          isDefault: true
          editable: true
    service:
      type: ClusterIP
      port: 80
    EOF
  ]
}

resource "kubernetes_config_map" "grafana_dashboard" {
  metadata {
    name      = "grafana-dashboard"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"
    }
  }

  data = {
    "pq-dashboard.json" = file("${path.module}/pq-dashboard.json")
  }
}

resource "kubernetes_namespace" "database" {
  metadata {
    name = "database"
  }
}

resource "helm_release" "postgresql" {
  depends_on = [kubernetes_namespace.database]

  name       = "postgresql"
  repository = "https://charts.bitnami.com/bitnami"
  chart      = "postgresql"
  namespace  = kubernetes_namespace.database.metadata[0].name

  values = [
    <<EOF
    global:
      postgresql:
        auth:
          postgresPassword: "admin"
          username: "sa"
          password: "admin"
          database: "backend"
    postgresql:
      auth:
        postgresPassword: "admin"
        username: "sa"
        password: "admin"
        database: "backend"
    metrics:
      enabled: true
      image:
        registry: docker.io
        repository: bitnami/postgres-exporter
        tag: 0.10.0
      serviceMonitor:
        enabled: true
        additionalLabels:
          release: prometheus-operator
        namespace: monitoring
        interval: 30s
        path: /metrics
    primary:
      initdb:
        scripts:
          my_init_script.sh: |
            #!/bin/sh
            echo "Creating tables and inserting initial data"
            PGPASSWORD=admin psql -U "$POSTGRESQL_USERNAME" -d "$POSTGRESQL_DATABASE" <<EOF
            \c backend;

            -- Create the sequence manually, set MINVALUE to 0, and start from 0
            CREATE SEQUENCE equipos_id_seq MINVALUE 0 START 0;

            create table equipos (
                id integer PRIMARY KEY DEFAULT nextval('equipos_id_seq'),
                nombre_seleccion varchar(80),
                CONSTRAINT nombreunico UNIQUE (nombre_seleccion)
            );

            -- Alter the table to set the default value for the id column
            ALTER TABLE equipos ALTER COLUMN id SET DEFAULT nextval('equipos_id_seq');

            create table  usuario (
                ci integer primary key not null,
                username text not null,
                contrasena text not null,
                id_campeon integer,
                id_subcampeon integer,
                es_admin integer default 0,
                CONSTRAINT fk_id_e1 FOREIGN KEY(id_campeon) REFERENCES equipos(id),
                CONSTRAINT fk_id_e2 FOREIGN KEY(id_subcampeon) REFERENCES equipos(id)
            );

            create table  partidos (
                id serial primary key ,
                fecha timestamp with time zone ,
                etapa text,
                id_equipo1 integer,
                id_equipo2 integer,
                id_ganador integer,
                id_perdedor integer,
                goles_ganador integer,
                goles_perdedor integer,
                penales_ganador integer,
                penales_perdedor integer,
                CONSTRAINT fk_id_e1 FOREIGN KEY(id_equipo1) REFERENCES equipos(id),
                CONSTRAINT fk_id_e2 FOREIGN KEY(id_equipo2) REFERENCES equipos(id),
                CONSTRAINT fk_id_g FOREIGN KEY(id_ganador) REFERENCES equipos(id),
                CONSTRAINT fk_id_p FOREIGN KEY(id_perdedor) REFERENCES equipos(id),
                CONSTRAINT check_idwinner CHECK (id_ganador = id_equipo1 OR id_ganador = id_equipo2),
                CONSTRAINT check_idlooser CHECK (id_perdedor = id_equipo1 OR id_perdedor = id_equipo2),
                CONSTRAINT check_goles_ganador CHECK (goles_ganador >= goles_perdedor ),
                CONSTRAINT check_goles_perdedor CHECK (goles_perdedor <= goles_ganador ),
                CONSTRAINT check_penales_ganador CHECK ( penales_ganador is null OR penales_ganador > penales_perdedor ),
                CONSTRAINT check_penales_perdedor CHECK ( penales_perdedor is null OR penales_perdedor < penales_ganador ),
                CONSTRAINT check_penales_not_null CHECK ( (penales_perdedor is null AND penales_ganador is null) OR (penales_perdedor is not null AND penales_ganador is not null) )
            );

            create table predicciones (
                id serial primary key ,
                ci_usuario integer not null,
                id_partido integer,
                id_ganador integer,
                id_perdedor integer,
                goles_ganador integer,
                goles_perdedor integer,
                penales_ganador integer,
                penales_perdedor integer,
                CONSTRAINT onecibyteam UNIQUE (ci_usuario, id_partido),
                CONSTRAINT fk_usuario FOREIGN KEY(ci_usuario) REFERENCES usuario(ci),
                CONSTRAINT fk_id_g FOREIGN KEY(id_ganador) REFERENCES equipos(id),
                CONSTRAINT fk_id_p FOREIGN KEY(id_perdedor) REFERENCES equipos(id),
                CONSTRAINT fk_id_partido FOREIGN KEY(id_partido) REFERENCES partidos(id),
                CONSTRAINT check_goles_ganador CHECK (goles_ganador >= goles_perdedor ),
                CONSTRAINT check_goles_perdedor CHECK (goles_perdedor <= goles_ganador ),
                CONSTRAINT check_penales_ganador CHECK ( penales_ganador is null OR penales_ganador > penales_perdedor ),
                CONSTRAINT check_penales_perdedor CHECK ( penales_perdedor is null OR penales_perdedor < penales_ganador ),
                CONSTRAINT check_penales_not_null CHECK ( (penales_perdedor is null AND penales_ganador is null) OR (penales_perdedor is not null AND penales_ganador is not null) )
            );


            --refers to users points
            create table puntos (
                ci_usuario integer primary key,
                puntos integer default 0,
                CONSTRAINT fk_usuario FOREIGN KEY(ci_usuario) REFERENCES usuario(ci),
                CONSTRAINT check_points CHECK (puntos >= 0)
            );

            create table posiciones (
                id_equipo integer primary key,
                puntos integer not null default 0, 
                diferenciagoles integer not null default 0,
                CONSTRAINT fk_id_partido FOREIGN KEY(id_equipo) REFERENCES equipos(id)
            );

            --trigger 
            CREATE OR REPLACE FUNCTION puntaje_final() RETURNS TRIGGER AS $$
            BEGIN
                IF NEW.id = 32 THEN
                    -- Award points to users who correctly predicted the champion
                    UPDATE puntos
                    SET puntos = puntos + 10
                    FROM usuario
                    WHERE usuario.id_campeon = NEW.id_ganador
                      AND puntos.ci_usuario = usuario.ci;

                    -- Award points to users who correctly predicted the runner-up
                    UPDATE puntos
                    SET puntos = puntos + 5
                    FROM usuario
                    WHERE usuario.id_subcampeon = NEW.id_perdedor
                      AND puntos.ci_usuario = usuario.ci;
                END IF;
                RETURN NEW;
            END;
            $$ LANGUAGE plpgsql;

            CREATE TRIGGER trigger_puntaje_final
            AFTER UPDATE ON partidos
            FOR EACH ROW
            EXECUTE FUNCTION puntaje_final();




            --Startup data

            --Agrego los Equipos
            INSERT INTO equipos (nombre_seleccion) VALUES 
            ('Argentina'),--0
            ('Perú'),--1
            ('Chile'),--2
            ('Canadá'),--3
            ('México'),--4
            ('Ecuador'),--5
            ('Venezuela'),--6
            ('Jamaica'),--7
            ('Estados Unidos'),--8
            ('Uruguay'),--9
            ('Panamá'),--10
            ('Bolivia'),--11
            ('Brasil'),--12
            ('Colombia'),--13
            ('Paraguay'),--14
            ('Costa Rica');--15

            --insert the temams in the table of positions, to simplify the sql query
            INSERT INTO posiciones (id_equipo, puntos, diferenciagoles) VALUES
            (0, 0 , 0),
            (1, 0 , 0),
            (2, 0 , 0),
            (3, 0 , 0),
            (4, 0 , 0),
            (5, 0 , 0),
            (6, 0 , 0),
            (7, 0 , 0),
            (8, 0 , 0),
            (9, 0 , 0),
            (10, 0 , 0),
            (11, 0 , 0),
            (12, 0 , 0),
            (13, 0 , 0),
            (14, 0 , 0),
            (15, 0 , 0);

            --Ingreso los partidos
            --https://copaamerica.com/calendario-de-partidos/

            --Ojo al guardarlo el pg lo convierte a utc (el middleware cambia al datenow a utc antes de chequear)
            INSERT INTO partidos (fecha, etapa, id_equipo1, id_equipo2) VALUES
            ('2024-06-20 20:00:00-04', 'Grupo A', 0 ,3),--1
            ('2024-06-21 19:00:00-05', 'Grupo A', 1 ,2),--2
            ('2024-06-22 20:00:00-05', 'Grupo B', 4 ,7),--3
            ('2024-06-22 15:00:00-07', 'Grupo B', 5 ,6),--4
            ('2024-06-23 17:00:00-05', 'Grupo C', 8 , 11),--5
            ('2024-06-23 21:00:00-04', 'Grupo C', 9 , 10),--6
            ('2024-06-24 18:00:00-07', 'Grupo D', 12 , 15),--7
            ('2024-06-24 17:00:00-05', 'Grupo D', 13 , 14),--8
            ('2024-06-25 21:00:00-04', 'Grupo A', 2 , 0),--9
            ('2024-06-25 17:00:00-05', 'Grupo A', 1 , 3),--10
            ('2024-06-26 18:00:00-07', 'Grupo B', 6 , 4),--11
            ('2024-06-26 15:00:00-07', 'Grupo B', 5 , 7),--12
            ('2024-06-27 18:00:00-04', 'Grupo C', 10 , 8),--13
            ('2024-06-27 21:00:00-04', 'Grupo C', 9 , 11),--14
            ('2024-06-28 18:00:00-07', 'Grupo D', 14 , 12),--15
            ('2024-06-28 15:00:00-07', 'Grupo D', 13 , 15),--16
            ('2024-06-29 21:00:00-04', 'Grupo A', 0 , 1),--17
            ('2024-06-29 20:00:00-04', 'Grupo A', 3 , 2),--18
            ('2024-06-30 17:00:00-07', 'Grupo B', 4 , 5),--19
            ('2024-06-30 19:00:00-05', 'Grupo B', 7 , 6),--20
            ('2024-07-01 20:00:00-05', 'Grupo C', 8 , 9),--21
            ('2024-07-01 21:00:00-04', 'Grupo C', 11 , 10),--22
            ('2024-07-02 18:00:00-07', 'Grupo D', 12 , 13),--23
            ('2024-07-02 20:00:00-05', 'Grupo D', 15 , 14),--24
            ('2024-07-04 20:00:00-05', 'Cuartos de Final', null , null), --25  1A VS 2B
            ('2024-07-05 20:00:00+00', 'Cuartos de Final', null , null), --26  1B VS 2A
            ('2024-07-06 18:00:00+00', 'Cuartos de Final', null , null), --27  1C VS 2D
            ('2024-07-06 15:00:00+00', 'Cuartos de Final', null , null), --28  1D VS 2C
            ('2024-07-09 20:00:00+00', 'Semifinales', null , null), --29   G25 vs G26
            ('2024-07-10 20:00:00+00', 'Semifinales', null , null), --30   G27 vs G28
            ('2024-07-13 20:00:00+00', '3er Puesto', null , null), --31   P29 vs P30
            ('2024-07-14 20:00:00+00', 'Final', null , null);--32  G29 vs G30


            --creo el admin
            INSERT INTO usuario(ci, username, contrasena, id_campeon, id_subcampeon, es_admin) VALUES ( 666, 'admin@test.com', 'x61Ey612Kl2gpFL56FT9weDnpSo4AV8j8+qx2AuTHdRyY036xxzTTrw10Wq3+4qQyB+XURPWx1ONxp3Y3pB37A==', 0,1,1); --Pass: admin

            EOF
  ]
}

# Define a namespace (optional)
resource "kubernetes_namespace" "penca-ucu" {
  metadata {
    name = "penca-ucu"
  }
}


# Deployment for backend and frontend
resource "kubernetes_deployment" "penca-ucu" {
  # depends_on = [kubernetes_namespace.penca-ucu, null_resource.build_frontend, null_resource.build_backend, helm_release.postgresql]
  metadata {
    name      = "penca-ucu"
    namespace = kubernetes_namespace.penca-ucu.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "penca-ucu"
      }
    }

    template {
      metadata {
        labels = {
          app = "penca-ucu"
        }
      }

      spec {
        container {
          name  = "backend"
          image = "pencaucu_backend:latest"
          image_pull_policy = "Never" 

          port {
            container_port = 3000
          }
        }

        container {
          name  = "frontend"
          image = "pencaucu_frontend:latest"
          image_pull_policy = "Never" 
        }
      }
    }
  }
}

# Service for the frontend
resource "kubernetes_service" "frontend" {
  metadata {
    name      = "penca-ucu-frontend"
    namespace = kubernetes_namespace.penca-ucu.metadata[0].name
  }

  spec {
    selector = {
      app = "penca-ucu"
    }

    port {
      port        = 80
      target_port = 80
    }

    type = "NodePort"
  }
}

# Service for the backend
resource "kubernetes_service" "backend" {
  metadata {
    name      = "penca-ucu-backend"
    namespace = kubernetes_namespace.penca-ucu.metadata[0].name
  }

  spec {
    selector = {
      app = "penca-ucu"
    }

    port {
      port        = 3000
      target_port = 3000
    }

    type = "NodePort"
  }
}

# resource "null_resource" "destroy_resources" {
#   provisioner "local-exec" {
#     when    = destroy
#     command = <<EOT
#     #!/bin/bash
#     set -x
#     # Delete Kubernetes resources
#     kubectl delete namespace monitoring
#     kubectl delete namespace database
#     EOT
#   }
# }
