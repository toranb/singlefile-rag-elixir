toran =
  %PhoenixDemo.User{name: "toran billups"}
  |> PhoenixDemo.Repo.insert!()

apple_rep =
  %PhoenixDemo.User{name: "apple rep"}
  |> PhoenixDemo.Repo.insert!()

spotify_rep =
  %PhoenixDemo.User{name: "spotify rep"}
  |> PhoenixDemo.Repo.insert!()

sprint_rep =
  %PhoenixDemo.User{name: "sprint rep"}
  |> PhoenixDemo.Repo.insert!()

symantec_rep =
  %PhoenixDemo.User{name: "symantec rep"}
  |> PhoenixDemo.Repo.insert!()

######
apple =
  %PhoenixDemo.Thread{title: "apple"}
  |> PhoenixDemo.Repo.insert!()

spotify =
  %PhoenixDemo.Thread{title: "spotify"}
  |> PhoenixDemo.Repo.insert!()

sprint =
  %PhoenixDemo.Thread{title: "sprint"}
  |> PhoenixDemo.Repo.insert!()

symantec =
  %PhoenixDemo.Thread{title: "symantec"}
  |> PhoenixDemo.Repo.insert!()

######
text = "So the new update does not let me listen to music and go on whatsapp at the same time"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

apple_one =
  %PhoenixDemo.Message{thread_id: apple.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text =
  "Hi Toran! Help is here. Can you check if logging out and restarting your device and logging back in makes a difference?"

%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

apple_two =
  %PhoenixDemo.Message{thread_id: apple.id, user_id: apple_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "What is the exact iOS you are using? Are you using any specific apps when noticing this?"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

apple_three =
  %PhoenixDemo.Message{thread_id: apple.id, user_id: apple_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text =
  "I'm on iOS 17.0.1. I have read the help page turned off virtually all apps and location svs too but in typing this I dropped 3% battery life"

%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

apple_four =
  %PhoenixDemo.Message{thread_id: apple.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "This looks like a bug in that release, go to settings > general > software update and download the latest version"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

apple_five =
  %PhoenixDemo.Message{thread_id: apple.id, user_id: apple_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

###### Spotify
text = "I've noticed a peculiar error message popping up on my screen. It says 'error code e84'. How can I fix this?"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

spotify_one =
  %PhoenixDemo.Message{thread_id: spotify.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "I've tried to double checked the device settings but I'm not sure what needs configured correctly."
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

spotify_two =
  %PhoenixDemo.Message{thread_id: spotify.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "To resolve this error please enable JavaScript. Sorry for the inconvenience."
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

spotify_three =
  %PhoenixDemo.Message{thread_id: spotify.id, user_id: spotify_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

###### Sprint
text = "I'm having trouble connecting to my home Wi-Fi network. It doesn't detect any networks, although other devices are connecting fine. What can be done to resolve this issue?"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

sprint_one =
  %PhoenixDemo.Message{thread_id: sprint.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "Thank you for your question. The first thing that we recommend is updating the software on your router. After you update the software reboot your device and it should be fully operational."
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

sprint_two =
  %PhoenixDemo.Message{thread_id: sprint.id, user_id: sprint_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "I tried different settings and configurations but failed to check for software updates. I did the software update and it seems to be working now. Thanks again for the help!"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

sprint_three =
  %PhoenixDemo.Message{thread_id: sprint.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "Thank you! Have a great day!"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

sprint_four =
  %PhoenixDemo.Message{thread_id: sprint.id, user_id: sprint_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

###### Symantec symantec
text = "This morning, my computer is running at an agonizingly sluggish pace. Can you please help me with this?"
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

symantec_one =
  %PhoenixDemo.Message{thread_id: symantec.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "This problem started after the recent virus definition update. I haven't made any other changes to the system."
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

symantec_two =
  %PhoenixDemo.Message{thread_id: symantec.id, user_id: toran.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()

text = "Unfortunately, this does require that you reinstall the antivirus software. Please report back if that does not solve your problem."
%{embedding: embedding} = Nx.Serving.batched_run(SentenceTransformer, text)

symantec_three =
  %PhoenixDemo.Message{thread_id: symantec.id, user_id: symantec_rep.id, text: text, embedding: embedding}
  |> PhoenixDemo.Repo.insert!()
