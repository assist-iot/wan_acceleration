# start by pulling the python image
FROM python:3.8-alpine

LABEL Maintainer="rreisim@upv.es"

# switch working directory
WORKDIR /app

# copy the requirements file into the image
COPY . ./

# install the dependencies and packages in the requirements file
RUN pip3 install -r requirements.txt

ENV PYTHONUNBUFFERED=1

# configure the container to run in an executed manner
ENTRYPOINT [ "python3" ]

CMD ["view.py" ]