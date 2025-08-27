class DomainError(Exception):
    """Base de errores de dominio (negocio)."""

class NotFound(DomainError):
    """Recurso no encontrado."""

class BadInput(DomainError):
    """Entrada inválida/valores fuera de contrato."""
