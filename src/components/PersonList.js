import React from 'react';
import axios from 'axios';

export default class PersonList extends React.Component {
  state = {
    persons: []
  }

  componentDidMount() {
    axios.get(`https://uo5dtmbygh.execute-api.us-west-2.amazonaws.com/group1-stage/get-todo-group1`)
      .then(res => {
        const persons = res.data.body;
        this.setState({ persons });
      })
  }

  render() {
    return (
      <ul>
        {
          this.state.persons
            .map(person =>
              <li key={person.id}>{person.id}{person.name}</li>
            )
        }
      </ul>
    )
  }
}