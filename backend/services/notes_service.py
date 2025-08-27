from datetime import timedelta
from backend.schemas.notes import validate_create_note
from backend.repos.notes_repo import create_note as repo_create, list_notes as repo_list
from backend.errors import BadInput

def create(data, now, fp):
    try:
        text, hours = validate_create_note(data)
    except ValueError as e:
        raise BadInput(str(e))
    return repo_create(text, now, now + timedelta(hours=hours), fp)

def list_(page: int, per_page: int, now):
    return repo_list(page, per_page)
