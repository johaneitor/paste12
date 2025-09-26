from backend import create_app  # type: ignore
application = create_app()
# alias por compatibilidad con algunas plataformas
app = application
