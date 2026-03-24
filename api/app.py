import os
import time
import json
from datetime import datetime
from flask import Flask, request, jsonify, g
from ldap3 import Server, Connection, ServerPool, ALL, SUBTREE, ROUND_ROBIN
from google.oauth2 import id_token
from google.auth.transport import requests as google_requests

# === OTLP IMPORTS ===
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.instrumentation.flask import FlaskInstrumentor
from opentelemetry.instrumentation.requests import RequestsInstrumentor

# === OTLP CONFIGURATION ===
resource = Resource(attributes={"service.name": "api-mantenimiento-acme"})
provider = TracerProvider(resource=resource)
trace.set_tracer_provider(provider)

# OTLP gRPC endpoint
otlp_exporter = OTLPSpanExporter(endpoint="http://100.89.164.46:4317", insecure=True)
provider.add_span_processor(BatchSpanProcessor(otlp_exporter))

tracer = trace.get_tracer(__name__)

app = Flask(__name__)

# Instrumentar Flask
FlaskInstrumentor().instrument_app(app)
RequestsInstrumentor().instrument()

# Configuración Legacy (Windows AD) con Failover automático
AD_PRIMARY_IP = os.environ.get('AD_SERVER_IP', '10.0.1.2')
AD_REPLICA_IP = os.environ.get('AD_REPLICA_IP', '10.0.1.3')
DOMAIN = 'acme.local'

# ServerPool: si el PDC se cae, ldap3 probará automáticamente con la Réplica
ad_server_pool = ServerPool([
    Server(AD_PRIMARY_IP, get_info=ALL),
    Server(AD_REPLICA_IP, get_info=ALL)
], ROUND_ROBIN, active=True, exhaust=True)

# Configuración Moderna (GCP Identity)
GCP_CLIENT_ID = os.environ.get('GCP_CLIENT_ID', 'tu-client-id.apps.googleusercontent.com')

# --- Middleware de Logging JSON para Promtail/Loki + TraceID ---
@app.before_request
def start_timer():
    g.start_time = time.time()

@app.after_request
def log_request(response):
    if request.path == '/health':
        return response # No loguear el healthcheck constante
        
    response_time_ms = round((time.time() - g.start_time) * 1000, 2)
    
    log_entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "method": request.method,
        "path": request.path,
        "status": response.status_code,
        "response_time_ms": response_time_ms,
        "remote_addr": request.remote_addr,
        "service": "api-mantenimiento"
    }
    
    # Extraer el Trace ID de OTLP e inyectarlo en el JSON
    current_span = trace.get_current_span()
    if current_span and current_span.get_span_context().is_valid:
        trace_id = format(current_span.get_span_context().trace_id, '032x')
        log_entry["traceID"] = trace_id
    
    # Imprime en stdout (Docker → Promtail lo recoge de aquí)
    print(json.dumps(log_entry), flush=True)
    return response
# ----------------------------------------------------------------

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok"}), 200

# MÉTODO 1: TRADICIONAL (LDAP contra Windows Server)
@app.route('/api/v1/mantenimiento/legacy', methods=['POST'])
def mantenimiento_legacy():
    data = request.json or {}
    usuario = data.get('usuario')
    password = data.get('password')

    if not usuario or not password:
        return jsonify({"error": "Faltan credenciales"}), 400

    user_upn = f"{usuario}@{DOMAIN}"
    
    with tracer.start_as_current_span("AD_LDAP_Auth_Flow") as span:
        span.set_attribute("ad.primary_ip", AD_PRIMARY_IP)
        span.set_attribute("ad.replica_ip", AD_REPLICA_IP)
        span.set_attribute("ad.upn", user_upn)
        
        try:
            span.add_event("Binding to Active Directory (ServerPool failover)...")
            conn = Connection(ad_server_pool, user=user_upn, password=password, auto_bind=True)
            
            span.add_event("Reading user groups...")
            conn.search(search_base='DC=acme,DC=local', 
                        search_filter=f'(sAMAccountName={usuario})', 
                        search_scope=SUBTREE, 
                        attributes=['memberOf'])
            
            grupos = str(conn.entries[0].memberOf.values if conn.entries else [])
            span.set_attribute("ad.groups_read", len(grupos))
            
            if "Mecanicos_Grupo" in grupos:
                span.set_attribute("auth.status", "success")
                return jsonify({"auth": "LDAP_Windows", "status": "Acceso concedido al taller."}), 200
                
            span.set_attribute("auth.status", "forbidden_group")
            return jsonify({"error": "No eres mecánico en el AD tradicional"}), 403
            
        except Exception as e:
            span.record_exception(e)
            span.set_attribute("auth.status", "failed_bind")
            return jsonify({"error": "Fallo de LDAP", "details": str(e)}), 401


# MÉTODO 2: MODERNO (Validación de Token de Google Cloud Identity)
@app.route('/api/v2/mantenimiento/cloud', methods=['POST'])
def mantenimiento_cloud():
    auth_header = request.headers.get('Authorization')
    if not auth_header or not auth_header.startswith('Bearer '):
        return jsonify({"error": "Falta el token OAuth de Google"}), 401
        
    token = auth_header.split(' ')[1]
    
    with tracer.start_as_current_span("GCP_JWT_Validation") as span:
        try:
            span.add_event("Verifying OAuth2 Signature via python-google-auth...")
            id_info = id_token.verify_oauth2_token(token, google_requests.Request(), GCP_CLIENT_ID)
            
            email_usuario = id_info.get('email', '')
            span.set_attribute("gcp.user_email", email_usuario)
            
            if email_usuario.endswith('@acme.es'):
                span.set_attribute("auth.status", "success")
                return jsonify({
                    "auth": "GCP_Identity", 
                    "usuario": email_usuario,
                    "status": "Acceso validado vía Google Cloud IAM."
                }), 200
            else:
                span.set_attribute("auth.status", "forbidden_domain")
                return jsonify({"error": "Dominio no autorizado"}), 403
                
        except ValueError as e:
            span.record_exception(e)
            span.set_attribute("auth.status", "invalid_token")
            return jsonify({"error": "Token de Google inválido o expirado"}), 401

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)
