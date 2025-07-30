FROM node:16.18

WORKDIR /frontend-react-js

COPY package*.json .

RUN npm install

COPY . .

ENV PORT=3000

EXPOSE 3000

CMD ["npm", "start"]
