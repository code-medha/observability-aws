FROM python:3.10-slim-buster

WORKDIR /backend-flask

COPY requirements.txt .

RUN pip3 install -r requirements.txt

COPY . .

ENV FLASK_ENV=development

EXPOSE 5000

CMD [ "python3", "-m" , "flask", "run", "--host=0.0.0.0", "--port=5000", "--reload"]
