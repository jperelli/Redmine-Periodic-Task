FROM redmine:6.0-bookworm

RUN echo "development:\n  adapter: sqlite3\n  database: /usr/src/redmine/sqlite/redmine.db" > /usr/src/redmine/config/database.yml
RUN mkdir -p /usr/src/redmine/sqlite
RUN chown -R 999:999 /usr/src/redmine/sqlite

RUN apt update && apt install -y gcc make
COPY ./Gemfile /usr/src/redmine/plugins/periodictask/Gemfile
RUN bundle install --with=development

ENTRYPOINT [ "" ]

CMD [ "rails", "server", "-e", "development", "-b", "0.0.0.0" ]
